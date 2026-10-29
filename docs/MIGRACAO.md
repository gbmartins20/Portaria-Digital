# Migração do AppSheet

Não foram recebidos dados tabulares reais. O PRD não substitui uma exportação das tabelas. A migração permanece pendente e não altera o AppSheet.

## Preparação

1. Exporte todas as linhas autorizadas, inclusive antigas fora do filtro de sete dias.
2. Conte registros por origem, grupos abertos, acompanhantes e volumes. Guarde uma cópia original protegida.
3. Concilie o papel da tabela `Visitantes` e dos campos `Qtd_*`/`Visitantes_Gerados`. **Não importe uma projeção estatística junto com os responsáveis e acompanhantes**, pois isso duplicaria pessoas.
4. Cadastre/importe cidades, empresas, veículos e tipos. Obtenha seus novos UUIDs pelo painel/consulta administrativa.
5. Converta cada grupo do legado em um único objeto canônico. Anexe os acompanhantes por `ID_Visita_Pai`; não colete nomes de acompanhantes.
6. Resolva datas/horários sem fuso ou saídas apenas em HH:mm antes da importação. Nunca invente o dia de uma saída ambígua.

## Arquivo canônico

Uma lista JSON, sem senhas, contendo:

```json
[
  {
    "source": "responsavel",
    "source_id": "ID_ORIGINAL_DO_APPSHEET",
    "record": {
      "module": "visitor",
      "name": "NOME ORIGINAL",
      "sex": "M",
      "age": "21-35",
      "city_id": "UUID_DA_CIDADE_CADASTRADA",
      "plate": "ABC1D23",
      "phone": "",
      "entry_at": "2026-10-28T09:00:00-03:00",
      "exit_at": "2026-10-28T10:00:00-03:00",
      "companions": [{ "sex": "F", "age": "5-15" }]
    },
    "legacy": { "operador_original": "IDENTIFICAÇÃO ORIGINAL", "tabela_original": "Responsável" }
  }
]
```

Valores como `UUID_DA_CIDADE_CADASTRADA` são **marcadores do formato**, não dados para importar.

| Origem canônica | Módulo | Dados adicionais obrigatórios |
|---|---|---|
| `responsavel` | `visitor` | sexo, faixa, cidade e acompanhantes vinculados |
| `registro_residuos` | `disposal` | vehicle_id, plate, driver, company_name, type_id |
| `saida_materiais` | `material` | vehicle_id, plate, driver, type_id, quantity |
| `registro_servico` | `service` | vehicle_id do cadastro de serviço, plate, driver, company_name, vehicle_label |

Para materiais e resíduos: `quantity` aceita decimal, `location` guarda origem/destino e `note` a observação. A empresa/cidade/tipo são copiados como fotografia do evento; revisões posteriores dos cadastros não alteram os registros importados.

`legacy` preserva os dados de origem para conciliação. `created_by` identifica quem fez a importação; não se inventa um usuário novo para simular a autoria histórica.

## Simular e aplicar

```sh
node scripts/import-legacy.mjs /caminho/protegido/legado.json
```

A ferramenta solicita uma linha JSON com `email` e `password` do administrador **por stdin**, com entrada oculta. Utilize um terminal privado ou gerenciador de segredos; não coloque senha em argumentos do shell, arquivos versionados ou logs.

Sem `--apply`, o banco valida e reverte cada lote, sem criar visitas ou auditoria da simulação. Corrija todas as inconsistências antes de aplicar:

```sh
node scripts/import-legacy.mjs /caminho/protegido/legado.json --apply
```

Lotes têm até 200 grupos e são transacionais. Se um lote posterior falhar, os anteriores podem já estar gravados; repetir é seguro porque `(source, source_id)` é único. IDs repetidos são ignorados e contabilizados, não sobrescritos.

A tabela `Visitantes` não é uma origem aceita automaticamente. Se a conciliação demonstrar que contém registros independentes, revise o mapeamento com o responsável antes de converter.

## Conciliação e corte

Compare contagens de grupos, responsáveis, acompanhantes, veículos, abertos, encerrados e volumes por período/tipo. Teste repetição sem duplicatas. Homologue lado a lado com o AppSheet e com as capturas de tela originais.

Faça backup final e defina janela de corte. Durante o piloto, preserve acesso de consulta ao legado. Em caso de retorno, reconcilie primeiro os lançamentos realizados no sistema novo.
