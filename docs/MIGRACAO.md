# Migração do AppSheet

As exportações são conciliadas por origem e identificador. A importação preserva os lançamentos existentes no aplicativo e não altera o AppSheet.

## Exportação Excel original

`scripts/prepare-workbook.py` lê as 13 abas do arquivo de origem com a biblioteca padrão do Python. O resultado contém um manifesto e lotes determinísticos de até 500 linhas. O diretório de saída deve ficar fora do repositório, pois contém dados pessoais. Nunca envie a planilha, os lotes ou os arquivos SQL preenchidos ao GitHub.

```sh
python scripts/prepare-workbook.py /caminho/arquivo.xlsx /caminho/protegido/importacao \
  --existing-catalogs /caminho/protegido/cadastros.json --snapshot-date AAAA-MM-DD
```

`cadastros.json` é uma consulta administrativa dos cadastros atuais. A data deve ser a data confirmada da exportação em Brasília. IDs UUID são determinísticos. Os cadastros existentes são reutilizados sem sobrescrever seus dados.

| Origem | Destino e regra |
|---|---|
| Responsável + Acompanhantes | Um atendimento por responsável e seus acompanhantes vinculados pelo ID original. Campos demográficos ausentes permanecem ausentes. |
| Visitantes com pai conhecido | Projeção do grupo, preservada em `legacy_rows`, sem novo atendimento. Divergências são sinalizadas no grupo. |
| Visitantes sem pai no cadastro de responsáveis | Atendimento histórico individual. Linhas sem ID recebem uma identidade vinculada ao arquivo e à linha, sem presumir que pessoas iguais sejam a mesma visita. |
| Resíduos, materiais e serviços | Um atendimento por ID original, com valores históricos e referências resolvidas sem distinção de maiúsculas. |
| Cadastros auxiliares | Municípios, empresas, veículos, condutores e tipos. Placas repetidas com dados divergentes ficam inativas para conferência. Condutores homônimos recebem a placa no rótulo, mantendo o nome preenchido no registro. |
| Acompanhante sem pai | Linha original preservada com pendência. Nenhum vínculo, data ou responsável é inventado. |

Todas as linhas não vazias, tipos das células e fórmulas originais são preservados em tabelas privadas com acesso direto bloqueado. O cabeçalho de cada aba fica no manifesto. `legacy_batches` registra o hash SHA-256 do arquivo, o responsável pela importação e os totais esperados. `legacy_rows` vincula cada linha ao atendimento, acompanhante ou cadastro correspondente.

O carregador `app_private.load_workbook_chunk` é exclusivo da conexão administrativa e não tem permissão de execução para `anon`, `authenticated` ou `service_role`. Use uma conexão administrativa autorizada e uma conta administrativa ativa como autora da importação. Inicialize o manifesto, carregue cadastros e simule **todos** os lotes de atendimentos em transações revertidas. Depois aplique atendimentos, acompanhantes e arquivo original, nessa ordem. Cada lote é transacional e pode ser retomado sem duplicar IDs.

`app_private.finish_workbook` só conclui o lote depois de conferir todas as abas, contagens por módulo, acompanhantes, projeções, vínculos, rastreabilidade e volumes. Também compara os registros, acompanhantes e cadastros anteriores com os hashes capturados no início. Não altere a flag de conclusão manualmente.

Datas e horas parciais não recebem valores de preenchimento. Uma quantidade ausente não vira zero. Saída anterior à entrada sem dia explícito não é transferida automaticamente para o dia seguinte. Esses atendimentos aparecem no histórico como **Saída a conferir**. Apenas uma entrada na data confirmada da exportação com saída vazia é mantida em aberto. Horários completos, inclusive saídas em outro dia, são preservados. O aplicativo mostra as pendências e exporta a origem, a linha e as observações de conferência.

Os campos obrigatórios continuam valendo para os novos atendimentos. A exceção de histórico incompleto exige um lote privado de migração e não pode ser ativada pelo formulário ou pela API pública.

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
