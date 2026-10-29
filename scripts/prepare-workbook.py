"""Read an AppSheet XLSX export and prepare private, deterministic import chunks.

Only Python's standard library is used. Never write the output inside the repo.
No credentials, source records or compiled SQL belong in version control.
"""
import argparse
import collections
import datetime as dt
import hashlib
import json
import posixpath
import re
import uuid
import zipfile
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from xml.etree import ElementTree as ET

NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'
NAMESPACE = uuid.UUID('76a3c9a4-fc3c-53b1-bdbd-d3ef10dd417c')
EPOCH = dt.datetime(1899, 12, 30)
BR = dt.timezone(dt.timedelta(hours=-3))
AGES = {'0-4', '5-15', '16-20', '21-35', '36-59', '60+'}


def uid(key):
    return str(uuid.uuid5(NAMESPACE, key))


def norm(value):
    return re.sub(r'\s+', ' ', str(value or '').strip()).upper()


def plate(value):
    raw = norm(value)
    normalized = re.sub('[^A-Z0-9]', '', raw)
    return normalized if re.fullmatch(r'[A-Z]{3}[0-9][A-Z0-9][0-9]{2}', normalized) else raw


def source_key(value):
    value = str(value or '').strip()
    return value[:-2] if re.fullmatch(r'\d+\.0', value) else value


def read_xlsx(path):
    with zipfile.ZipFile(path) as z:
        strings = []
        if 'xl/sharedStrings.xml' in z.namelist():
            strings = [''.join(t.text or '' for t in si.iter('{'+NS['m']+'}t'))
                       for si in ET.fromstring(z.read('xl/sharedStrings.xml'))]
        wb = ET.fromstring(z.read('xl/workbook.xml'))
        props = wb.find('m:workbookPr', NS)
        if props is not None and props.get('date1904') in ('1', 'true'):
            raise ValueError('Esta exportação usa o calendário Excel 1904; conversão não autorizada.')
        rels = {r.attrib['Id']: r.attrib['Target'] for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
        result = {}
        for sheet in wb.find('m:sheets', NS):
            target = rels[sheet.attrib[REL]]
            target = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/'+target)
            xml = ET.fromstring(z.read(target))
            rows = []
            for row in xml.findall('m:sheetData/m:row', NS):
                values, formulas, types = {}, {}, {}
                for c in row:
                    ref = c.attrib['r']
                    col = re.sub(r'\d', '', ref)
                    kind = c.get('t', 'n')
                    v, f = c.find('m:v', NS), c.find('m:f', NS)
                    raw = v.text if v is not None else None
                    if kind == 's':
                        value = strings[int(raw)] if raw is not None else ''
                    elif kind == 'inlineStr':
                        value = ''.join(c.find('m:is', NS).itertext())
                    elif kind == 'b':
                        value = raw == '1'
                    else:
                        value = raw
                    if f is not None:
                        formulas[col] = f.text
                    if value is not None and value != '':
                        values[col] = value
                        types[col] = kind
                if values:
                    rows.append({'row': int(row.get('r')), 'cells': values, 'formulas': formulas, 'types': types})
            result[sheet.get('name')] = {'headers': rows[0]['cells'], 'rows': rows[1:]}
        return result


def excel_day(value):
    try:
        n = Decimal(str(value))
        if not Decimal(30000) <= n <= Decimal(80000):
            return None
        return (EPOCH+dt.timedelta(days=int(n))).date()
    except Exception:
        return None


def excel_clock(value):
    """Return a clock and, for full serial timestamps, its explicit calendar day."""
    try:
        n = Decimal(str(value))
        if n < 0 or n > 80000:
            return None, None
        seconds = int(((n % 1)*86400).quantize(Decimal('1'), rounding=ROUND_HALF_UP))
        seconds = min(seconds, 86399)
        clock = (EPOCH+dt.timedelta(seconds=seconds)).time()
        return clock, excel_day(value) if n >= 1 else None
    except Exception:
        if isinstance(value, str) and re.fullmatch(r'\d{1,2}:\d{2}(:\d{2})?', value.strip()):
            try:
                return dt.time.fromisoformat(value.strip().zfill(5)), None
            except ValueError:
                pass
        return None, None


def timeline(date_value, entry_value, exit_value, today):
    issues = []
    source_date = excel_day(date_value)
    ec, ed = excel_clock(entry_value)
    xc, xd = excel_clock(exit_value)
    day = ed or source_date
    if source_date is None:
        issues.append('Data ausente ou inválida no legado.')
    if ec is None:
        issues.append('Horário de entrada ausente ou inválido no legado.')
    if ed and source_date and ed != source_date:
        issues.append('Data da entrada difere da coluna Data no legado.')
    entry = dt.datetime.combine(day, ec, BR) if day and ec else None
    exit_at = dt.datetime.combine(xd or day, xc, BR) if (xd or day) and xc else None
    is_open = not exit_value and bool(entry and entry.date() == today)
    if exit_at and entry and exit_at < entry:
        issues.append('Saída anterior à entrada no legado; dia da saída precisa de conferência.')
        exit_at = None
    elif xc is None and not is_open:
        issues.append('Horário de saída ausente ou inválido no legado.')
    return {
        'entry_at': entry.isoformat() if entry else None,
        'exit_at': exit_at.isoformat() if exit_at else None,
        'legacy': {'visit_date': day.isoformat() if day else None,
                   'source_date': source_date.isoformat() if source_date else None,
                   'entry_time': ec.isoformat() if ec else None,
                   'exit_time': xc.isoformat() if xc else None,
                   'open_at_import': is_open}, 'issues': issues}


def prepare(path, existing, today):
    sheets = read_xlsx(path)
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    batch = uid('workbook:'+sha)
    source_rows = {s: [r['cells'] | {'_row': r['row']} for r in v['rows']] for s, v in sheets.items()}
    required = {'Visitantes','Responsável','Acompanhantes','Registro_Resíduos','Saída_Materiais','Registro_Serviço',
                'Cidades','Empresas','Veiculos','Tipos_Residuo','Tipos_Residuo_Saída','Veículos_Serviço','Sexo'}
    if set(sheets) != required:
        raise ValueError('Abas diferentes do mapeamento revisado: '+str(set(sheets)^required))
    catalogs, catalog_index, archive_index = [], {}, {}
    for c in existing:
        catalog_index[(c['kind'], norm(c['name']))] = c
    lookup = {}
    archive = []
    for s, v in sheets.items():
        lookup[s] = {source_key(r['A']).casefold(): r for r in source_rows[s] if r.get('A')}
        for row in v['rows']:
            record = {'sheet_name': s, 'row_number': row['row'], 'source_id': source_key(row['cells'].get('A')) or None,
                      'raw_data': {'cells': row['cells'], 'types': row['types']}, 'formulas': row['formulas'],
                      'classification': 'unlinked', 'record_id': None, 'catalog_id': None, 'companion_id': None, 'issues': []}
            archive.append(record)
            archive_index[(s, row['row'])] = record

    def catalog(kind, name, data=None, active=True):
        name = norm(name)
        if not name:
            return None
        key = (kind, name)
        if key in catalog_index:
            return catalog_index[key]
        c = {'id': uid('catalog:'+kind+':'+name), 'kind': kind, 'name': name, 'data': data or {}, 'active': active}
        if len(name) > 200:
            raise ValueError('Nome de cadastro acima de 200 caracteres.')
        catalogs.append({'data': c})
        catalog_index[key] = c
        return c

    def find(sheet, value):
        return lookup[sheet].get(source_key(value).casefold())

    def annotate_catalog(sheet, row, c):
        a = archive_index[(sheet, row['_row'])]
        a['classification'] = 'catalog'
        a['catalog_id'] = c['id'] if c else None

    def company(value):
        known = find('Empresas', value)
        name = norm(known['B'] if known else value)
        if name:
            catalog('company', name)
        return name

    for r in source_rows['Cidades']:
        annotate_catalog('Cidades', r, catalog('city', r['B'], {'uf': ''}))
    for r in source_rows['Empresas']:
        annotate_catalog('Empresas', r, catalog('company', r['B']))
    for s, kind in [('Tipos_Residuo','waste'), ('Tipos_Residuo_Saída','material')]:
        for r in source_rows[s]:
            annotate_catalog(s, r, catalog(kind, r['B']))

    vehicle_by_source, service_by_source = {}, {}
    for s, kind in [('Veiculos', 'vehicle'), ('Veículos_Serviço', 'service')]:
        used_names = collections.Counter(norm(r['D']) for r in source_rows[s]) if kind == 'service' else {}
        for r in source_rows[s]:
            pl, driver, co = plate(r.get('B')), norm(r.get('D')), company(r.get('C'))
            label = norm(r.get('E'))
            valid = bool(re.fullmatch(r'[A-Z]{3}[0-9][A-Z0-9][0-9]{2}', pl) and driver and co and (label or kind == 'vehicle'))
            name = pl if kind == 'vehicle' else driver
            if kind == 'service' and used_names[driver] > 1:
                name = driver+' · '+(pl or source_key(r['A']))
            c = catalog(kind, name, {'plate': pl, 'driver': driver, 'company': co, 'vehicle': label,
                                    **({'driver_name':driver} if kind=='service' else {}),
                                    'legacy_source': s, 'legacy_id': source_key(r['A'])}, valid)
            if kind=='vehicle' and c and c['data'].get('legacy_source')==s and (c['data'].get('driver',''),c['data'].get('company',''))!=(driver,co):
                c['active']=False
                c['data']['legacy_conflict']='Placa repetida com condutor ou empresa divergentes. Confira as linhas originais antes de ativar.'
                archive_index[(s,r['_row'])]['issues'].append(c['data']['legacy_conflict'])
            annotate_catalog(s, r, c)
            (vehicle_by_source if kind == 'vehicle' else service_by_source)[source_key(r['A']).casefold()] = c

    projected = collections.defaultdict(list)
    companions_by_parent = collections.defaultdict(list)
    parents = {source_key(r['A']): r for r in source_rows['Responsável']}
    for r in source_rows['Visitantes']:
        if source_key(r.get('B')) in parents:
            projected[source_key(r['B'])].append(r)
    for r in source_rows['Acompanhantes']:
        companions_by_parent[source_key(r.get('B'))].append(r)
    records, companions, parent_ids = [], [], {}
    group_discrepancies = 0

    def city(value, snapshot, uf, issues):
        known = find('Cidades', value)
        name = norm(snapshot or (known['B'] if known else value))
        if re.fullmatch(r'[A-F0-9]{8}', name or ''):
            issues.append('Referência de município não localizada no cadastro original.')
            return None, ''
        if not name:
            issues.append('Município não informado no legado.')
            return None, ''
        c = catalog('city', name, {'uf': norm(uf)})
        return c['id'], name

    def add_record(sheet, row, source, source_id, module, fields, date_col, entry_col, exit_col, extra_issues=None):
        sid = source_id or ('arquivo:'+sha+':linha:'+str(row['_row']))
        rid = uid('record:'+source+':'+sid)
        t = timeline(row.get(date_col), row.get(entry_col), row.get(exit_col), today)
        issues = list(extra_issues or [])+t['issues']
        legacy = t['legacy'] | {'sheet': sheet, 'row': row['_row'], 'source_id': source_id,
                                 'issues': issues, 'entry_operator': '', 'exit_operator': ''}
        if module == 'visitor' and sheet == 'Visitantes':
            legacy.update(entry_operator=row.get('R',''), exit_operator=row.get('S',''))
        elif module == 'disposal':
            legacy.update(entry_operator=row.get('S',''), exit_operator=row.get('T',''))
        elif module == 'service':
            legacy.update(entry_operator=row.get('K',''), exit_operator=row.get('L',''))
        data = {'id': rid, 'request_key': uid('request:'+source+':'+sid), 'module': module,
                'name': '', 'sex': '', 'age': '', 'city_id': None, 'city_name': '', 'phone': '', 'plate': '',
                'vehicle_id': None, 'driver': '', 'company_name': '', 'vehicle_label': '', 'type_id': None,
                'type_name': '', 'quantity': 0, 'location': '', 'note': '', **fields,
                'entry_at': t['entry_at'], 'exit_at': t['exit_at'], 'legacy': legacy}
        if len(data['name']) > 160 or len(data['plate']) > 20 or len(data['note']) > 4000:
            issues.append('Texto histórico acima do limite dos formulários atuais; conteúdo original preservado.')
        records.append({'source': source, 'source_id': sid, 'data': data,
                        'legacy': {'sheet': sheet, 'row': row['_row'], 'file_sha256': sha}})
        a = archive_index[(sheet, row['_row'])]
        a.update(classification='record', record_id=rid, issues=issues)
        return data

    for r in source_rows['Responsável']:
        key = source_key(r['A'])
        issues = []
        ci, cn = city(r.get('G'), r.get('H'), r.get('I'), issues)
        expected = collections.Counter([(r.get('E'), r.get('F'))]+[(c.get('D'),c.get('E')) for c in companions_by_parent[key]])
        actual = collections.Counter((v.get('H'),v.get('I')) for v in projected[key])
        if expected != actual:
            issues.append('A projeção Visitantes diverge do responsável e dos acompanhantes; fontes originais preservadas para conferência.')
            group_discrepancies += 1
        rec = add_record('Responsável', r, 'responsavel', key, 'visitor', {
            'name': norm(r.get('D')), 'sex': r['E'], 'age': r['F'], 'city_id': ci, 'city_name': cn,
            'phone': str(r.get('K','')), 'plate': plate(r.get('J'))}, 'B','M','N', issues)
        parent_ids[key] = rec['id']
        for ordinal, c in enumerate(companions_by_parent[key], 1):
            cid = uid('companion:'+source_key(c['A']))
            missing = []
            if not c.get('D'):
                missing.append('Sexo do acompanhante ausente no legado.')
            if not c.get('E'):
                missing.append('Faixa etária do acompanhante ausente no legado.')
            companions.append({'data': {'id': cid, 'record_id': rec['id'], 'ordinal': ordinal,
                                       'sex': c.get('D'), 'age': c.get('E'),
                                       'legacy': {'source_id': source_key(c['A']), 'row': c['_row'], 'issues': missing}}})
            archive_index[('Acompanhantes', c['_row'])].update(classification='companion', record_id=rec['id'], companion_id=cid, issues=missing)
            if missing and 'Há acompanhantes com dados ausentes no legado.' not in rec['legacy']['issues']:
                rec['legacy']['issues'].append('Há acompanhantes com dados ausentes no legado.')
        for v in projected[key]:
            archive_index[('Visitantes', v['_row'])].update(classification='projection', record_id=rec['id'])

    for r in source_rows['Visitantes']:
        if source_key(r.get('B')) in parents:
            continue
        issues = []
        if not r.get('H'):
            issues.append('Sexo ausente no legado.')
        if not r.get('I'):
            issues.append('Faixa etária ausente no legado.')
        elif r['I'] not in AGES:
            issues.append('Faixa etária histórica diferente das faixas atuais; valor original mantido.')
        ci, cn = city(r.get('J'), r.get('K'), r.get('L'), issues)
        add_record('Visitantes', r, 'visitantes_independentes', source_key(r.get('A')), 'visitor', {
            'name': norm(r.get('G')), 'sex': r.get('H',''), 'age': r.get('I',''), 'city_id': ci, 'city_name': cn,
            'phone': str(r.get('N','')), 'plate': plate(r.get('M'))}, 'C','O','P', issues)

    def vehicle(ref, snapshot, driver, co, issues):
        c = vehicle_by_source.get(source_key(ref).casefold())
        pl = plate(snapshot or (c['data'].get('plate') if c else ''))
        if not pl and ref and re.fullmatch(r'[A-Z]{3}[0-9][A-Z0-9][0-9]{2}', plate(ref)):
            pl = plate(ref)
        if not pl:
            issues.append('Placa não localizada no legado.')
        dr, co = norm(driver), company(co)
        if not dr:
            issues.append('Condutor não informado no registro original.')
        if not c and pl:
            valid = bool(re.fullmatch(r'[A-Z]{3}[0-9][A-Z0-9][0-9]{2}', pl) and dr and co)
            c = catalog('vehicle', pl, {'plate': pl, 'driver': dr, 'company': co, 'vehicle': '', 'legacy_source': 'historico'}, valid)
        return c, pl, dr, co

    for s, module, cols, source in [
        ('Registro_Resíduos','disposal',{'ref':'H','pl':'I','driver':'Q','company':'G','type':'J','qty':'K','location':'L','note':'R','entry':'M','exit':'N'},'registro_residuos'),
        ('Saída_Materiais','material',{'ref':'G','pl':'H','driver':'I','company':'J','type':'K','qty':'L','location':'M','note':'N','entry':'O','exit':'P'},'saida_materiais')]:
        for r in source_rows[s]:
            issues = []
            c, pl, dr, co = vehicle(r.get(cols['ref']),r.get(cols['pl']),r.get(cols['driver']),r.get(cols['company']),issues)
            typ = r.get(cols['type'],'')
            known = find('Tipos_Residuo' if module == 'disposal' else 'Tipos_Residuo_Saída', typ)
            tn = norm(known['B'] if known else typ)
            if not known and re.fullmatch(r'[A-Z0-9]{6,8}',tn) and any(ch.isdigit() for ch in tn):
                issues.append('Referência do tipo de material não localizada no cadastro original.')
                tc, tn = None, 'REFERÊNCIA NÃO LOCALIZADA ('+tn+')'
            else:
                tc = catalog('waste' if module == 'disposal' else 'material', tn)
            qty = Decimal(r[cols['qty']]) if r.get(cols['qty']) else None
            if qty is None:
                issues.append('Quantidade não informada no legado; não foi convertida para zero.')
            elif qty < 0 or qty.as_tuple().exponent < -3:
                raise ValueError(f'Quantidade fora da precisão em {s} linha {r["_row"]}.')
            add_record(s,r,source,source_key(r['A']),module,{
                'vehicle_id': c['id'] if c else None,'plate':pl,'driver':dr,'company_name':co,
                'type_id':tc['id'] if tc else None,'type_name':tn,'quantity':str(qty) if qty is not None else None,
                'location':str(r.get(cols['location'],'')),'note':str(r.get(cols['note'],''))},'B',cols['entry'],cols['exit'],issues)

    for r in source_rows['Registro_Serviço']:
        issues = []
        c = service_by_source.get(source_key(r.get('E')).casefold())
        known = find('Veículos_Serviço',r.get('E'))
        dr = norm(r.get('F') or (known.get('D') if known else ''))
        pl, co, label = plate(r.get('C')),company(r.get('D')),norm(r.get('G'))
        if not dr:
            issues.append('Nome do condutor não localizado no legado.')
        if not label:
            issues.append('Veículo não informado no registro original.')
        if not c and dr:
            c = catalog('service',dr,{'plate':pl,'driver':dr,'driver_name':dr,'company':co,'vehicle':label,'legacy_source':'historico'}, bool(re.fullmatch(r'[A-Z]{3}[0-9][A-Z0-9][0-9]{2}',pl) and co and label))
        add_record('Registro_Serviço',r,'registro_servico',source_key(r['A']),'service',{
            'vehicle_id':c['id'] if c else None,'plate':pl,'driver':dr,'company_name':co,'vehicle_label':label,'note':str(r.get('H',''))},'B','I','J',issues)

    for a in archive:
        if a['classification'] == 'unlinked':
            a['issues'].append('Acompanhante sem ID_Visita_Pai; vínculo não foi inventado.')
    totals = collections.Counter(r['data']['module'] for r in records)
    quantities = {m:str(sum((Decimal(r['data']['quantity']) for r in records if r['data']['module']==m and r['data']['quantity'] is not None),Decimal(0))) for m in ('disposal','material')}
    manifest = {'timezone':'America/Sao_Paulo','snapshot_date':today.isoformat(),
                'sheets':{s:{'rows':len(v['rows']),'headers':v['headers']} for s,v in sheets.items()},
                'expected':{'source_rows':len(archive),'records':len(records),'by_module':dict(totals),'companions':len(companions),
                            'new_catalogs':len(catalogs),'quantity_sums':quantities,
                            'projections':sum(a['classification']=='projection' for a in archive),
                            'unlinked':sum(a['classification']=='unlinked' for a in archive)},
                'group_discrepancies':group_discrepancies,
                'policy':'Responsável + Acompanhantes são a fonte dos grupos. Visitantes com pai conhecido é projeção. Demais Visitantes são registros independentes. Campos ausentes não são inferidos. Saídas sem dia certo ficam para conferência. Somente entrada na data da exportação com saída vazia é mantida em aberto.'}
    return {'batch':batch,'source_name':path.name,'sha256':sha,'manifest':manifest,'catalogs':catalogs,'records':records,'companions':companions,'archive':archive}


def sql_literal(value):
    return "'"+json.dumps(value,ensure_ascii=False,separators=(',',':')).replace("'","''")+"'::jsonb"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('xlsx', type=Path)
    ap.add_argument('output', type=Path)
    ap.add_argument('--existing-catalogs', type=Path, required=True)
    ap.add_argument('--snapshot-date', type=dt.date.fromisoformat, required=True)
    args = ap.parse_args()
    repo = Path(__file__).resolve().parents[1]
    if args.output.resolve().is_relative_to(repo):
        raise ValueError('O diretório de dados pessoais deve ficar fora do repositório.')
    prepared = prepare(args.xlsx,json.loads(args.existing_catalogs.read_text()),args.snapshot_date)
    args.output.mkdir(parents=True,exist_ok=True,mode=0o700)
    (args.output/'prepared.json').write_text(json.dumps(prepared,ensure_ascii=False,separators=(',',':')))
    (args.output/'manifest.json').write_text(json.dumps({k:v for k,v in prepared.items() if k not in ('catalogs','records','companions','archive')},ensure_ascii=False,indent=2))
    chunks = []
    sections = [('begin',[{k:prepared[k] for k in ('source_name','sha256','manifest')}])]+[(k,prepared[k]) for k in ('catalogs','records','companions','archive')]
    for section, rows in sections:
        for start in range(0,len(rows),500):
            piece = rows[start:start+500]
            chunks.append({'section':section,'offset':start,'rows':piece})
    (args.output/'chunks.json').write_text(json.dumps(chunks,ensure_ascii=False,separators=(',',':')))
    print(json.dumps({'batch':prepared['batch'],'sha256':prepared['sha256'],**prepared['manifest']['expected'],'group_discrepancies':prepared['manifest']['group_discrepancies'],'chunks':len(chunks)},ensure_ascii=False))


if __name__ == '__main__':
    main()
