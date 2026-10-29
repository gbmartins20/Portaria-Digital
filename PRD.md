# PRD — Portaria Digital

**Unidade:** Parque Municipal Roberto Pereira Inocêncio (Roberto Cação), Rio das Ostras/RJ  
**Versão:** 1.0 — 29/10/2026  
**Status:** requisitos documentados para validação; não constitui autorização para desenvolver ou publicar o aplicativo.  
**Responsável pelo produto:** Gabriel Martins de Oliveira / Administração do PMU.

## 1. Resumo executivo

Substituir o aplicativo Portaria Digital desenvolvido em AppSheet por uma aplicação web independente do Google, com banco de dados controlado pelo projeto, preservando a organização visual e os procedimentos já conhecidos pelos colaboradores da portaria.

O produto registrará entradas e saídas de visitantes e seus acompanhantes, veículos de descarte, veículos de retirada de materiais e pessoas a serviço. As listas operacionais apresentarão movimentações abertas; os respectivos históricos apresentarão movimentações encerradas.

**Regra central:** uma visita é um grupo formado por um responsável e zero ou mais acompanhantes. O operador cadastra os acompanhantes dentro do formulário do responsável. Salvar confirma o grupo inteiro. Registrar a saída do responsável encerra, em uma única operação indivisível, a visita de todas as pessoas do grupo.

Objetivo financeiro: operar inicialmente sem mensalidade, quando o volume e os termos dos fornecedores permitirem. Gratuidade permanente não pode ser garantida. Independência do Google não significa ausência de fornecedores: o sistema deverá permitir exportação e migração para outro ambiente PostgreSQL.

## 2. Fontes e grau de certeza

### 2.1 Fontes utilizadas

- PDF `Documentação do Portaria Digital - Appsheet.pdf`, gerado em 27/10/2026 às 10:35:33, versão documentada 2,000032.
- Capturas de tela fornecidas: listas dos quatro módulos, menu lateral, formulários e formulário de acompanhantes.
- Explicação expressa de Gabriel sobre cadastro e baixa conjunta de responsável e acompanhantes.
- Documentação oficial de fornecedores consultada em 29/10/2026, referenciada na seção 20.

### 2.2 Classificação

| Classificação | Significado |
| --- | --- |
| Confirmado | Visível nas telas, descrito nas configurações ou explicado diretamente pelo responsável |
| Proposto | Decisão recomendada para o novo produto; não é afirmação sobre o comportamento atual |
| A validar | Informação insuficiente ou divergente; exige confirmação antes da implementação correspondente |

A documentação exportada contém 16 tabelas, 166 colunas, oito fatias, 56 visualizações e 81 ações. Esses números descrevem o AppSheet e não são metas de complexidade para o novo sistema. Há tabelas técnicas, campos auxiliares e textos antigos; não se deve reproduzir automaticamente toda essa estrutura.

**Precedência:** explicação atual do responsável → telas operacionais → configurações específicas → textos descritivos gerais. Divergências não devem ser resolvidas copiando defeitos técnicos do legado.

## 3. Problema e objetivos

### 3.1 Problema

O AppSheet limita a evolução e a autonomia do aplicativo. A substituição precisa eliminar essa dependência sem introduzir uma rotina desconhecida na portaria ou perder vínculos, horários e históricos.

### 3.2 Objetivos verificáveis

1. Oferecer os mesmos quatro caminhos principais, na mesma ordem.
2. Permitir cadastro e baixa de grupos sem lançar cada passageiro separadamente na lista principal.
3. Preservar pesquisa, preenchimento assistido, consulta histórica e identificação dos operadores.
4. Impedir registros parciais, baixas duplicadas e perda silenciosa de dados.
5. Manter dados exportáveis e restauração documentada.
6. Começar em infraestrutura gratuita, se compatível com a operação institucional.

### 3.3 Indicadores propostos

| Indicador | Meta inicial / forma de avaliação |
| --- | --- |
| Grupos gravados parcialmente | Zero nos testes e no piloto |
| Baixas parciais de grupos | Zero |
| Duplicação por clique ou reenvio | Zero |
| Tempo de atendimento | Igual ou inferior ao legado, medido com os mesmos cenários no piloto |
| Adaptação da equipe | Operadores concluem os quatro fluxos após orientação de até 30 minutos |
| Integridade da migração | Contagens e totais conciliados, com todas as divergências registradas |
| Recuperação | Restauração de backup demonstrada antes da entrada em produção |

## 4. Usuários e permissões

Perfis abaixo são **propostos**, pois a exportação não comprova uma matriz de autorização equivalente.

| Capacidade | Operador da portaria | Administrador |
| --- | --- | --- |
| Consultar listas abertas e históricos | Sim | Sim |
| Registrar entradas e saídas | Sim | Sim |
| Editar dados descritivos de registros abertos | Sim, com auditoria | Sim |
| Alterar horários automaticamente registrados | Não | Somente correção formal, com justificativa e trilha preservada |
| Corrigir ou cancelar registros encerrados | Não | Sim, com justificativa |
| Excluir definitivamente histórico pela interface | Não | Não |
| Gerenciar usuários e cadastros auxiliares | Não, salvo inclusão rápida autorizada | Sim |
| Exportar dados pessoais em lote | Não por padrão | Sim |
| Consultar auditoria e situação de backup | Não | Sim |

Contas individuais, criadas pela administração; sem cadastro público. Uma sessão deve identificar quem registrou a entrada e quem registrou a saída, inclusive quando forem pessoas diferentes. Bloquear conta desativada também nas operações de servidor. Recuperação de acesso não dependerá de login Google.

## 5. Escopo e prioridades

### 5.1 P0 — primeira versão operacional

- Autenticação e controle de permissões.
- Quatro módulos operacionais e quatro históricos.
- Cadastro de responsável com acompanhantes incorporados ao formulário.
- Salvamento e baixa transacionais do grupo.
- Pesquisa, detalhe, edição controlada e preenchimento assistido.
- Datas, horários, permanência e operador registrados automaticamente.
- Cadastros auxiliares necessários aos formulários.
- Interface responsiva fiel à organização atual.
- Migração conciliada, auditoria, exportação administrativa e backup restaurável.
- Tratamento explícito de perda de conexão e conflitos entre operadores.

### 5.2 P1 — evolução após homologação

- Painel estatístico com filtros demográficos, períodos e volumes.
- Instalação como PWA, caso não incluída no empacotamento inicial.
- Filtros avançados e relatórios formatados para impressão.
- Reabertura administrativa de movimentação encerrada incorretamente, se confirmada a necessidade.

### 5.3 Fora do escopo inicial

Reservas via COLAB, bilheteria, pagamentos, reconhecimento facial, biometria, leitura automática de placas, catracas, rastreamento por GPS, aplicativo nativo de loja, portal público de visitantes, gestão completa de estoque, comprovante ambiental de destinação e sincronização de gravações offline. Registro de descarte não representa, por si só, autorização ambiental ou documento de transporte.

## 6. Navegação e fidelidade visual

### 6.1 Estrutura principal confirmada

Barra superior em verde oliva, menu lateral à esquerda, brasão do município, busca e atualização à direita. Quatro abas inferiores persistentes, na ordem:

1. **Registrar Visitantes**.
2. **Registrar Descarte**.
3. **Registrar Saída de Materiais**.
4. **Registrar Pessoas à Serviços** — grafia atual; eventual ajuste para “Pessoas a Serviço” depende de aprovação de rótulo.

Menu lateral com **Histórico de Descarte**, **Histórico de Saídas**, **Histórico de Serviço** e **Histórico de Visitantes**. Exibir identificação do usuário e opção Sair. Gestão administrativa pode aparecer apenas para administradores.

Não reproduzir itens próprios do AppSheet, como App Gallery, Share e Feedback, nem ícones azuis de edição da ferramenta presentes nas capturas. A caixa de seleção superior só deve ser funcional se houver seleção em lote aprovada; não criar botão sem função.

### 6.2 Componentes

- Listas brancas com separadores horizontais, identificação em duas linhas e ações à direita.
- Botão flutuante “+” no canto inferior direito para novo registro do módulo ativo.
- Formulário branco, campos empilhados e mesmos rótulos e sequência das telas atuais.
- Barra inferior fixa com **Cancelar** e **Salvar**, sem cobrir campos ou teclado virtual.
- Brasão ao fundo em área escura/verde, sem prejudicar leitura; utilizar arquivo institucional autorizado e manter proporções.
- Manter linguagem simples em português brasileiro, foco visível e áreas de toque de pelo menos 44 × 44 px.
- Não incluir dashboards ou etapas extras no fluxo principal da portaria.
- Em celular estreito, permitir rótulos em mais de uma linha, sem cortar nomes dos módulos.

O tom exato das cores e o arquivo do brasão serão extraídos dos materiais oficiais na implementação; as capturas são referência visual, não especificação cromática definitiva.

### 6.3 Comportamento comum

Ao entrar no aplicativo, abrir Registrar Visitantes. Trocar de aba exibe apenas os registros abertos daquele módulo. Proposta: mais recentes primeiro, com ordenação estável por entrada e identificador. A busca filtra o módulo atual por seus campos relevantes. A atualização refaz a consulta e informa falhas; não deve repetir gravações.

Ao tocar em um registro, abrir os detalhes. Ações por ícone devem ter nome acessível. Ao cancelar um formulário alterado, pedir confirmação de descarte das alterações; cancelar não salva responsável, acompanhantes ou novos cadastros auxiliares inadvertidamente.

## 7. Visitantes e acompanhantes

### 7.1 Formulário do responsável

Obrigatoriedade abaixo segue os asteriscos visíveis nas telas; campos sem asterisco permanecem opcionais até validação.

| Ordem | Campo | Obrigatório | Regra |
| --- | --- | --- | --- |
| 1 | Nome | Não na tela; a validar | Texto; remover espaços nas extremidades; proposta de padronização em maiúsculas |
| 2 | Sexo | Sim | Botões M e F, conforme legado |
| 3 | Faixa Etária | Sim | 0-4, 5-15, 16-20, 21-35, 36-59, 60+ |
| 4 | Cidade | Sim | Seleção pesquisável de cadastro auxiliar |
| 5 | Telefone | Não | Texto com máscara amigável; não inventar telefone ausente |
| 6 | Placa do Veículo | Não | Entrada em maiúsculas; aceitar visita a pé sem placa |
| 7 | Adicione Todos os Passageiros do Veículo | Não | Lista incorporada e botão Adicionar |

Não exigir CPF, RG, data de nascimento, endereço ou nomes dos acompanhantes. Essas informações não aparecem no fluxo fornecido.

### 7.2 Formulário de acompanhante

| Campo | Regra |
| --- | --- |
| Sexo_Acompanhante | M ou F |
| Faixa_Etaria_Acompanhante | Mesmas seis faixas etárias do responsável |

A tela fornecida não pede nome. `Nome_Acompanhante`, encontrado na estrutura, pode ser identificador técnico e não deve virar exigência de identificação pessoal. Proposta: exigir sexo e faixa etária de cada acompanhante para preservar a estatística, confirmando essa obrigatoriedade na homologação.

Fluxo: tocar Adicionar → preencher acompanhante → Salvar retorna ao formulário do responsável → exibir resumo do acompanhante → repetir quando necessário → Salvar no formulário principal confirma todo o grupo. Salvar o subformulário apenas adiciona o acompanhante ao rascunho local; ainda não confirma a entrada no banco.

Permitir editar ou remover acompanhantes antes do salvamento principal. Exibir a contagem “1 responsável + N acompanhantes = T pessoas”. Nenhum acompanhante deve ser contado como outro veículo.

### 7.3 Regras do grupo

- **RF-V01:** cada visita tem um identificador estável, um responsável e zero ou mais acompanhantes.
- **RF-V02:** responsável sem acompanhante é uma visita válida.
- **RF-V03:** a lista principal apresenta uma linha por responsável/grupo, preservando o padrão atual: placa como identificação principal e nome como secundária; sem placa, apresentar nome com indicação “A pé”, proposta a validar.
- **RF-V04:** salvar responsável e acompanhantes em uma transação. Falha em qualquer item desfaz a operação inteira.
- **RF-V05:** entrada do grupo é um único instante, atribuído pelo servidor no salvamento confirmado.
- **RF-V06:** registrar saída pelo responsável encerra o grupo inteiro, com um único instante e um único operador de saída.
- **RF-V07:** acompanhante não possui botão de baixa individual na primeira versão.
- **RF-V08:** a saída só é permitida em grupo aberto; nova tentativa não altera o primeiro horário de saída.
- **RF-V09:** após a saída confirmada, o grupo deixa a lista operacional e aparece no Histórico de Visitantes com seus integrantes.
- **RF-V10:** voltar no navegador ou tocar Salvar duas vezes não cria novas visitas.
- **RF-V11:** retorno do mesmo responsável em outro momento cria nova visita; nunca reabrir automaticamente a anterior.
- **RF-V12:** edição posterior não gera novamente pessoas estatísticas já existentes.

**Exemplo obrigatório:** um motorista e três passageiros representam uma visita, quatro pessoas e um veículo. Ao baixar o motorista, as quatro pessoas recebem a mesma saída. Se o servidor falhar no encerramento, nenhuma das quatro será encerrada parcialmente.

### 7.4 Estatística e estrutura legada

A exportação contém tabelas Responsável, Acompanhantes e Visitantes, além de ações de geração de visitantes e campos de quantidades por sexo/faixa. A tela enviada mostra cadastro individual de acompanhantes; portanto esse será o fluxo inicial. Não transformar os campos de quantidade em uma nova grade na interface sem confirmação.

Para totais, contar o responsável uma vez e cada acompanhante uma vez. Se a tabela Visitantes for uma projeção gerada dos dois primeiros cadastros, não somar as três tabelas. O detalhe dessa geração deverá ser conciliado na migração. Cidade dos acompanhantes não é coletada individualmente: quando usada nos relatórios, indicar que é a cidade de referência do grupo.

## 8. Registrar Descarte

### 8.1 Formulário confirmado

| Ordem | Campo | Obrigatório na tela | Comportamento |
| --- | --- | --- | --- |
| 1 | Placa do Veículo | Sim | Seleção pesquisável de veículo cadastrado |
| 2 | Condutor | Sim | Texto; preenchimento assistido conforme cadastro do veículo |
| 3 | Empresa | Sim | Preenchimento assistido; associação validada |
| 4 | Tipo de Resíduo | Sim | Lista de tipos de entrada, importada do legado |
| 5 | Quantidade (m³) | Não | Inicial 0, botões − e +; permitir decimal |
| 6 | Origem (local de coleta) | Não | Texto |
| 7 | Observação | Não | Texto livre |

### 8.2 Requisitos

- **RF-D01:** salvar cria movimentação aberta com chegada automática e operador de entrada.
- **RF-D02:** lista exibe placa, condutor e empresa, como na captura.
- **RF-D03:** permitir registrar saída somente enquanto aberta; gravar instante e operador.
- **RF-D04:** após baixa, mover para Histórico de Descarte e calcular permanência.
- **RF-D05:** sugerir dados do veículo sem copiar horários ou informações da operação anterior.
- **RF-D06:** tipo de resíduo, quantidade, origem e observação pertencem à movimentação, não ao cadastro permanente do veículo.
- **RF-D07:** bloquear quantidade negativa, não numérica ou infinita; aceitar vírgula decimal na interface.
- **RF-D08:** não impedir encerramento apenas por quantidade igual a zero enquanto a regra de medição não for confirmada.

O valor final da quantidade antes ou depois da descarga, a inclusão rápida de veículo novo e a necessidade de múltiplos tipos de resíduos por carga são pontos a validar. A primeira versão reproduz um tipo por registro.

## 9. Registrar Saída de Materiais

### 9.1 Formulário confirmado

| Ordem | Campo | Obrigatório na tela | Comportamento |
| --- | --- | --- | --- |
| 1 | Placa | Sim | Seleção pesquisável de veículo |
| 2 | Condutor | Sim | Texto com preenchimento assistido |
| 3 | Empresa | Não | Texto ou vínculo auxiliar |
| 4 | Tipo de Material | Sim | Lista própria dos materiais de saída |
| 5 | Quantidade (m³) | Sim | Inicial 0; aceitar decimal; regra de valor zero a validar |
| 6 | Destino | Não | Texto |
| 7 | Observação | Não | Texto livre |

- **RF-M01:** criar registro pendente na chegada para retirada; entrada e saída são eventos diferentes.
- **RF-M02:** gravar entrada automaticamente ao salvar e saída somente quando acionada a baixa.
- **RF-M03:** transportar registro concluído para Histórico de Saídas.
- **RF-M04:** manter tipos de materiais de saída separados dos tipos de resíduos recebidos, mesmo quando os nomes coincidirem.
- **RF-M05:** validar quantidade não negativa e preenchimento obrigatório; o asterisco não comprova que zero é proibido.
- **RF-M06:** auditar operador de entrada e saída, mesmo que os campos não estejam presentes na tabela legada.

Proposta de lista: placa na primeira linha, condutor na segunda e empresa à direita. A captura mostra lista vazia; essa composição precisa de homologação. Não adicionar controle de saldo de estoque ou autorização eletrônica de retirada nesta fase.

## 10. Registrar Pessoas à Serviços

### 10.1 Formulário confirmado

| Ordem | Campo | Obrigatório na tela | Comportamento |
| --- | --- | --- | --- |
| 1 | Condutor | Sim | Seleção pesquisável de cadastro de serviço |
| 2 | Placa | Sim | Preenchimento assistido, editável conforme regra validada |
| 3 | Empresa | Sim | Preenchimento assistido |
| 4 | Veículo | Sim | Texto ou informação do cadastro; categorias a validar |
| 5 | Observação | Não | Texto livre |

- **RF-S01:** selecionar condutor sugere placa, empresa e veículo associados ao cadastro de serviço.
- **RF-S02:** criar nova movimentação a cada entrada; não reutilizar a linha histórica como registro aberto.
- **RF-S03:** lista exibe condutor, placa e empresa, conforme captura.
- **RF-S04:** disponibilizar edição controlada enquanto aberto e ação de saída.
- **RF-S05:** gravar entrada/saída e respectivos operadores; concluído vai para Histórico de Serviço.
- **RF-S06:** manter cadastro de serviço separado do cadastro de veículos de descarte quando as associações diferirem.

A tela inclui lixeira; no novo produto, a ação será cancelamento auditado, sujeito à permissão, e não apagamento definitivo. Fluxo de funcionário ou prestador a pé exige esclarecimento: a tela atual exige placa e veículo; não inventar uma placa fictícia para atender esse caso.

## 11. Históricos, busca e exportação

- **RF-H01:** oferecer os quatro históricos com seus nomes atuais.
- **RF-H02:** mostrar apenas registros encerrados por padrão; cancelados ficam em filtro separado, com motivo visível.
- **RF-H03:** permitir período, nome/condutor e placa; descarte e materiais também empresa e tipo; visitantes também cidade.
- **RF-H04:** permitir abrir detalhe completo e integrantes do grupo de visitantes.
- **RF-H05:** datas visíveis em DD/MM/AAAA e horários em HH:mm, com segundos disponíveis no detalhe/auditoria.
- **RF-H06:** filtrar um dia pelo intervalo entre sua meia-noite local e a meia-noite local do dia seguinte, sem misturar UTC com o dia brasileiro.
- **RF-H07:** usar paginação e consultas no servidor. Padrão proposto: 50 itens por página, sem limite artificial ao histórico consultável.
- **RF-H08:** o filtro legado de abertos ou últimos sete dias é uma otimização do AppSheet; não equivale a retenção nem autoriza apagar dados antigos.
- **RF-H09:** exportação CSV administrativa deve respeitar filtros, acentuação e separador adequado a pt-BR; neutralizar fórmulas de planilha em campos de texto.
- **RF-H10:** registrar quem exportou, quando e quais filtros utilizou; não produzir links públicos de exportação.

No Histórico de Visitantes, preservar data, nome, sexo, faixa etária, cidade, placa, telefone, entrada, saída e acesso aos acompanhantes. Campos técnicos como Visitantes_Gerados não precisam aparecer ao operador.

Indicadores mínimos verificáveis, ainda que inicialmente por consulta/exportação: grupos, pessoas, acompanhantes, veículos, entradas de descarte, saídas de materiais, volumes por tipo e movimentações de serviço. Separar “pessoas visitantes” de “movimentações de serviço”; um condutor de caminhão não deve automaticamente virar visitante estatístico.

## 12. Regras transversais e integridade

| ID | Regra |
| --- | --- |
| RN-01 | Estado operacional: aberto quando saída é nula; encerrado quando há saída; cancelado possui motivo e responsável |
| RN-02 | Entrada e saída usam data e hora completas; armazenar UTC e exibir America/Sao_Paulo |
| RN-03 | Permanência = saída − entrada; não subtrair apenas horas, evitando erro após meia-noite |
| RN-04 | Horários canônicos são definidos pelo servidor; o relógio do dispositivo não decide o horário confirmado |
| RN-05 | Nome/cidade/placa seguem normalização consistente; manter acentos e não alterar observações indiscriminadamente |
| RN-06 | Placas antigas e Mercosul são aceitas; normalizar espaços/hífen para comparação, preservando apresentação legível |
| RN-07 | Nova movimentação recebe chave idempotente; repetição da mesma requisição retorna o mesmo resultado |
| RN-08 | Baixa é condicionada ao estado aberto, com proteção de concorrência no banco |
| RN-09 | Edição usa versão do registro; alterações concorrentes não sobrescrevem dados silenciosamente |
| RN-10 | Avisar sobre placa já aberta no mesmo módulo; política de bloquear ou permitir mediante justificativa será validada |
| RN-11 | Cadastros desativados permanecem nos históricos; renomear empresa não reescreve a informação histórica |
| RN-12 | Correções mantêm antes/depois, autor, data e motivo; operadores não alteram logs |
| RN-13 | Não encerrar automaticamente pendências à meia-noite ou no fechamento do parque |
| RN-14 | Quantidades usam decimal exato no banco, nunca ponto flutuante para totais |
| RN-15 | Não usar nomes, placas ou telefones como chave primária de movimentações |

Proposta para baixa: preservar ação direta sem modal adicional, como o legado, e exibir retorno “Saída registrada”. Correção posterior cabe ao administrador; não oferecer desfazer que altere horários sem auditoria. Validação com a equipe poderá adotar confirmação se houver risco operacional observado.

## 13. Modelo de dados conceitual proposto

Não é uma migração SQL pronta. Nomes técnicos são sugestões; a implementação deve priorizar integridade e portabilidade.

| Entidade | Dados principais | Relações / restrições |
| --- | --- | --- |
| usuarios | id, identidade de autenticação, nome, perfil, ativo | Operadores de entrada/saída e autores de auditoria |
| visitas | id, dados do responsável, cidade de referência, telefone, placa, entrada, saída, autores, versão, cancelamento | Uma linha por grupo |
| acompanhantes | id, visita_id, sexo, faixa_etaria | FK obrigatória; não existe sem visita |
| cidades | id, nome normalizado, UF quando disponível, ativo | Referência pesquisável; preservar texto histórico |
| empresas | id, nome, ativo | Referências de veículos e movimentações |
| veiculos_operacionais | id, placa normalizada, empresa, condutor padrão, ativo | Descarte e retirada; placa não identifica o evento |
| tipos_residuo | id, nome, ativo | Entrada de resíduos |
| tipos_material_saida | id, nome, ativo | Retirada de materiais |
| descartes | id, veículo, placa/condutor/empresa históricos, tipo, volume, origem, observação, entrada/saída, autores, versão | Uma movimentação de recebimento |
| saidas_materiais | id, veículo, dados históricos, material, volume, destino, observação, entrada/saída, autores, versão | Uma movimentação de retirada |
| cadastros_servico | id, condutor, placa, empresa, veículo, ativo | Associações de preenchimento assistido |
| movimentacoes_servico | id, cadastro, dados históricos, observação, entrada/saída, autores, versão | Uma passagem a serviço |
| auditoria | id, autor, ação, entidade, registro, instante, justificativa, alterações | Escrita protegida, leitura restrita |
| importacoes_legado | lote, tabela/id original, destino, status e inconsistências | Rastreio e repetição segura da migração |

### 13.1 Responsável e acompanhantes

Preferência: guardar entrada/saída no grupo e obtê-las por vínculo para cada acompanhante. Isso garante que todos compartilhem o mesmo estado sem atualizações independentes. Se a implementação materializar pessoas para relatórios, deverá manter unicidade por integrante e atualização transacional; não armazenar cópias divergentes como fontes concorrentes de verdade.

### 13.2 Campos comuns e restrições

Movimentações terão identificador UUID ou equivalente, created_at, updated_at, entrada_at, saída_at anulável, created_by, closed_by, versão e dados de cancelamento. Saída não pode anteceder entrada; chaves estrangeiras são verificadas no banco. Acompanhantes não são apagados em cascata por exclusão operacional do responsável, pois a interface não oferece exclusão definitiva.

Dados históricos relevantes de veículo/empresa/condutor devem ser preservados como fotografia do evento. Índices iniciais propostos: entrada, saída nula, placa normalizada, chaves de relacionamento e campos de pesquisa; confirmar com volume real e planos de consulta.

### 13.3 Correspondência com o legado

| Origem AppSheet | Destino conceitual / tratamento |
| --- | --- |
| Responsável | visitas |
| Acompanhantes | acompanhantes, vinculados por ID_Visita_Pai |
| Visitantes | Conferir se projeção estatística ou registro autônomo antes de importar |
| Registro_Resíduos | descartes |
| Saída_Materiais | saidas_materiais |
| Registro_Serviço | movimentacoes_servico |
| Veiculos | veiculos_operacionais |
| Veículos_Serviço | cadastros_servico |
| Empresas, Cidades, Tipos_Residuo, Tipos_Residuo_Saída | Cadastros auxiliares correspondentes |
| Sexo e faixas | Domínios controlados, preservando valores legados |
| _Per User Settings e tabelas de processo do Bot | Não migrar como dados operacionais |
| Qtd_M_*, Qtd_F_* e Visitantes_Gerados | Validar função; não somar novamente acompanhantes já materializados |

## 14. Arquitetura e estratégia de custo

### 14.1 Proposta inicial

Aplicação web responsiva em TypeScript, com frontend estático quando possível, hospedagem HTTPS e backend PostgreSQL. Supabase é candidato para banco, autenticação e operações transacionais. Não é decisão irrevogável nem exige criar recursos agora.

Separar apresentação, regras de negócio e persistência. Cadastros, entrada e baixa são protegidos no servidor/banco; ocultar botões não substitui autorização. Operações de grupo precisam de endpoint ou função transacional única. Não depender de Google Sheets, AppSheet, Apps Script ou login Google.

Cloudflare Pages é uma opção a avaliar para frontend estático gratuito. A documentação consultada informa gratuidade de requisições estáticas e cotas próprias para funções; verificar novamente termos e capacidade antes de contratar/publicar. O plano Hobby da Vercel é apresentado como pessoal e não comercial; não presumir adequação a um sistema institucional municipal.

Supabase oferece plano gratuito, mas pode pausar projetos com pouca atividade durante sete dias. A documentação recomenda exportações e backups externos para projetos gratuitos. Logo, não tratar o plano gratuito como garantia de disponibilidade ou de recuperação automática.

### 14.2 Requisitos de custo e portabilidade

- Não ativar cobrança, contratar plano ou adquirir domínio como consequência deste PRD.
- Antes da implementação, medir volume diário, usuários simultâneos, histórico acumulado e crescimento.
- Registrar cotas vigentes de banco, tráfego, autenticação e funções no momento da escolha.
- Criar acompanhamento de consumo e avisos propostos a 70% e 90% das cotas mensuráveis.
- Priorizar paginação, consultas indexadas e ausência de upload de fotos/documentos no MVP.
- Exportar dados em formato aberto e manter migrações versionadas para PostgreSQL.
- Definir responsável institucional por contas, recuperação, propriedade dos dados e continuidade.
- Reavaliar custo se houver indisponibilidade recorrente, crescimento próximo da cota ou mudança de termos.

## 15. Segurança, privacidade e continuidade

### 15.1 Requisitos de acesso

- HTTPS em todas as operações; nenhuma consulta de dados pessoais disponível ao público.
- Autorizar operações por usuário ativo e perfil no backend. Na opção Supabase, habilitar RLS nas tabelas expostas e políticas adequadas à equipe do PMU.
- A base é institucional compartilhada entre operadores autorizados; não restringir cada linha apenas ao seu criador, o que impediria outro turno de registrar a saída.
- Chaves administrativas e segredos nunca vão para navegador, repositório público ou logs.
- Sessões expiradas não apagam o formulário sem aviso; reautenticar antes de confirmar operação.
- Dados pessoais não devem aparecer em logs técnicos, URLs públicas ou mensagens de erro.
- Não disponibilizar histórico completo em cache público nem no cache padrão de PWA.
- Registrar correções, cancelamentos, baixas e exportações. Restringir mudanças de perfil e trilha de auditoria.

### 15.2 Privacidade institucional

Coletar apenas dados previstos e necessários. Base legal, texto informativo, período de retenção, atendimento a solicitações e autorização institucional para uso dos fornecedores são **pendências administrativas**, não conclusões jurídicas deste PRD. Não reaproveitar automaticamente o texto legado que trata uso do aplicativo como consentimento do visitante.

Separar retenção do histórico da limitação visual de sete dias do AppSheet. Não definir exclusão automática até que o PMU determine política de retenção. Dados de acompanhantes permanecem limitados a sexo e faixa etária; não ampliar coleta por conveniência técnica.

### 15.3 Backup e contingência

Proposta inicial: backup diário criptografado, fora da conta/projeto principal, com retenção de 30 dias e restauração ensaiada antes da produção e a cada trimestre. Metas propostas: perda máxima de até 24 horas de dados (RPO) e recuperação em até quatro horas úteis (RTO), sujeitas à infraestrutura e equipe disponíveis.

Backup deve cobrir dados, esquema, políticas, funções e instruções de recuperação de usuários/acesso, sem guardar senhas em texto. Guardar segredos de restauração separadamente. Verificar falhas de backup e notificar o administrador pelo mecanismo que vier a ser autorizado.

Na indisponibilidade, seguir registro manual de contingência definido pelo PMU e posterior lançamento administrativo identificado. Guardar tanto o horário ocorrido quanto o horário da digitação e a justificativa; não fingir que o registro tardio foi capturado automaticamente no momento do acesso.

## 16. Conexão, desempenho e qualidade

### 16.1 Conexão

O MVP grava online. Sem internet, exibir “Sem conexão. O registro ainda não foi salvo.” e preservar o formulário em memória enquanto a sessão/página estiver aberta. Não mostrar sucesso sem confirmação do servidor.

Se houver timeout após enviar, consultar/repetir com a mesma chave idempotente antes de criar outra entrada. Mostrar “Verificando registro” quando o resultado for incerto. Atualizar listas após confirmação; outra estação deve poder atualizar manualmente. Atualização automática, se implementada, não deve interromper digitação e deve usar intervalo/custo validados no piloto.

Rascunho persistente no dispositivo e fila offline ficam fora do MVP, por exigirem regras adicionais de proteção, conflitos e horários. Explicar que fechar/recarregar a página pode perder um rascunho ainda não salvo.

### 16.2 Metas propostas de desempenho

| Operação | Meta de homologação |
| --- | --- |
| Abrir lista paginada | Até 2 s no percentil 95, em conexão estável |
| Salvar entrada ou saída | Até 3 s no percentil 95, excluindo falha de rede |
| Pesquisar cadastro | Até 1 s após requisição em conexão estável |
| Resposta visual ao toque | Estado de carregamento imediato, até 200 ms |
| Teste de carga inicial | 10 operadores simultâneos e 100 mil movimentações sintéticas, referência a ajustar ao volume real |

Dados sintéticos de teste não devem conter informações reais de visitantes. Compatibilidade mínima proposta: versões atuais de Chrome e Edge em computador e Chrome em Android; validar aparelhos efetivamente usados pela portaria. Testar larguras de 360 px até desktop, zoom de 200%, teclado e leitor de tela nos controles principais.

## 17. Migração e implantação futura

1. Obter exportação autorizada das tabelas reais, inclusive linhas antigas fora do filtro de sete dias. O PDF descreve estrutura, mas não substitui exportação dos dados.
2. Identificar contagens por tabela, registros abertos, vínculos de acompanhantes, faixas, cidades, empresas, veículos e tipos.
3. Confirmar a semântica da tabela Visitantes e dos campos Qtd_* para não duplicar pessoas.
4. Preservar identificadores originais em mapa de migração e converter datas segundo o fuso confirmado da origem.
5. Não inventar datas de saída para campos legados que armazenem apenas hora; marcar ambiguidade, especialmente após meia-noite.
6. Importar primeiro cadastros auxiliares, depois visitas/grupos e demais movimentações; detectar órfãos e duplicatas em relatório de exceções.
7. Reexecutar importação em homologação sem duplicar registros: chave única de origem por tabela e lote/identidade pertinente.
8. Conciliar grupos, integrantes, abertos/encerrados e volumes por tipo/período. Divergências precisam de resolução ou aceite registrado.
9. Homologar os fluxos com a equipe usando cenários conhecidos; revisar fidelidade visual lado a lado com as capturas.
10. Planejar janela de corte, backup final e importação incremental/final. Não escrever continuamente nos dois sistemas sem regra de conciliação.
11. Executar piloto supervisionado. Manter legado consultável e plano de retorno.
12. Em retorno ao legado, reconciliar antes as movimentações criadas no novo sistema; não descartar dados do piloto/produção.

Não há cronograma fechado sem conhecer qualidade e quantidade dos dados. Nenhuma etapa de implantação é executada pela entrega deste documento.

## 18. Critérios de aceite e cenários obrigatórios

| ID | Cenário | Resultado esperado |
| --- | --- | --- |
| CA-01 | Acesso sem sessão | Nenhum dado pessoal ou movimentação retornado |
| CA-02 | Operador navega pelas quatro abas | Mesma ordem, rótulos e ação + reconhecíveis |
| CA-03 | Responsável sem acompanhantes | Uma visita e uma pessoa gravadas |
| CA-04 | Responsável com três acompanhantes | Uma visita, quatro pessoas e um vínculo único de grupo |
| CA-05 | Cancelar formulário principal após adicionar passageiros | Nenhuma entrada ou acompanhante persistido |
| CA-06 | Falha ao gravar um acompanhante | Transação inteira revertida |
| CA-07 | Dar baixa no responsável do grupo | Todos encerrados no mesmo instante; grupo aparece no histórico |
| CA-08 | Duas estações dão baixa simultaneamente | Uma única saída; horário e operador originais preservados |
| CA-09 | Clique duplo em Salvar ou timeout com reenvio | Um único registro |
| CA-10 | Editar responsável já salvo | Não gerar visitantes duplicados |
| CA-11 | Entrada antes e saída após meia-noite | Permanência positiva e correta |
| CA-12 | Registro aberto há mais de sete dias | Continua visível na operação até ser encerrado |
| CA-13 | Selecionar placa de descarte conhecida | Condutor/empresa sugeridos; quantidade e tipo não herdados indevidamente |
| CA-14 | Descarte de 2,5 m³ | Decimal preservado e somado corretamente |
| CA-15 | Quantidade negativa | Salvamento bloqueado com mensagem junto ao campo |
| CA-16 | Retirada de material | Tipo de saída, destino e horários preservados no histórico correto |
| CA-17 | Selecionar condutor de serviço | Dados associados sugeridos; nova entrada independente das anteriores |
| CA-18 | Empresa alterada no cadastro após uma movimentação | Informação histórica original preservada |
| CA-19 | Filtro de um único dia brasileiro | Inclui todo o dia solicitado e nenhum registro do dia vizinho |
| CA-20 | Operador tenta exportar/administrar usuários sem permissão | Backend bloqueia mesmo por chamada direta |
| CA-21 | Rede cai antes de salvar | Mensagem de pendência; não mostrar sucesso |
| CA-22 | Cancelamento de registro | Motivo, autor e dados anteriores consultáveis; sem apagamento físico |
| CA-23 | Importação executada duas vezes | Nenhuma duplicação e relatório consistente |
| CA-24 | Comparar totais da migração | Responsável e passageiros contados uma vez cada |
| CA-25 | Restaurar backup em ambiente isolado | Dados, vínculos e permissões recuperados; procedimento documentado |
| CA-26 | Navegação no celular com teclado aberto | Campos e botões acessíveis, sem sobreposição que impeça atendimento |
| CA-27 | Sessão expira durante formulário | Reautenticação clara e nenhuma gravação atribuída ao usuário errado |

Critérios P0 são bloqueadores para substituição definitiva. Metas de desempenho devem ser medidas em ambiente equivalente ao de uso, com resultados registrados.

## 19. Perguntas de validação e decisões pendentes

Estas perguntas não impedem a entrega do PRD, mas não devem ser convertidas em fatos pelo desenvolvimento.

| Prioridade | Pergunta | Premissa provisória / impacto |
| --- | --- | --- |
| Alta | Nome do responsável é obrigatório na prática? | Tela sem asterisco: manter opcional até confirmação |
| Alta | Há visitantes e prestadores a pé? Como são registrados hoje? | Visitante sem placa é suportado; serviço sem placa depende de regra validada |
| Alta | Alguém do grupo sai antes ou depois do responsável? | Versão inicial somente baixa conjunta, conforme instrução atual |
| Alta | Acompanhantes sempre usam formulário individual ou também quantidades por faixa/sexo? | Usar formulário individual das capturas; não ativar grade legada automaticamente |
| Alta | Quem pode editar, cancelar e corrigir horários? | Aplicar matriz proposta com administrador responsável |
| Alta | A quantidade de material/descarga pode começar em zero e ser corrigida antes da saída? | Aceitar zero conforme telas; exigir não negativo |
| Alta | Como novos veículos, condutores, cidades e empresas entram no cadastro? | Administração gerencia; inclusão rápida depende de autorização definida |
| Alta | Quantos operadores, aparelhos e registros por dia? Qual a estabilidade da internet? | Dimensionamento e necessidade de offline dependem dessa resposta |
| Alta | Quais dados históricos devem migrar e qual o fuso efetivo da origem? | Não apagar nem presumir alcance da exportação filtrada |
| Alta | Quem assume contas institucionais, backup e recuperação? | Responsável precisa ser nomeado antes de produção |
| Média | Uma placa pode ter duas movimentações abertas no mesmo módulo? | Avisar; bloqueio depende da rotina confirmada |
| Média | Quais são exatamente os tipos de resíduos, materiais, cidades e empresas? | Importar cadastros reais; não inventar listas |
| Média | Condutor pode trocar de placa/empresa no mesmo atendimento? | Permitir revisão dos valores sugeridos sem alterar histórico de outros eventos |
| Média | É necessária confirmação antes da baixa? | Manter ação direta atual, com auditoria |
| Média | Precisam de exportação para todos ou apenas administração? | Exportação administrativa por padrão |
| Média | Serviço pode incluir acompanhantes ou equipes no mesmo veículo? | Não adicionar agrupamento ao módulo de serviço sem confirmação |
| Média | Qual o prazo institucional de retenção e quais relatórios são exigidos? | Sem exclusão automática; estatísticas básicas por consulta/exportação |

## 20. Referências técnicas consultadas

As referências abaixo sustentam apenas a avaliação de infraestrutura. Não substituem os requisitos de operação fornecidos pelo PMU. Condições comerciais precisam de nova verificação na implementação.

- Supabase — pausa por inatividade: https://supabase.com/docs/guides/platform/free-project-pausing
- Supabase — backups e recomendação de cópias externas para plano gratuito: https://supabase.com/docs/guides/platform/backups
- Cloudflare Pages — cobrança de requisições estáticas e funções: https://developers.cloudflare.com/pages/functions/pricing/
- Cloudflare Pages — limites: https://developers.cloudflare.com/pages/platform/limits/
- Vercel — condições do plano Hobby: https://vercel.com/docs/plans/hobby

## 21. Definição de pronto

A versão inicial estará pronta quando os requisitos P0 estiverem implementados e homologados, os cenários críticos passarem, os dados migrados estiverem conciliados, o backup tiver sido restaurado com sucesso, as contas e permissões estiverem validadas e a equipe conseguir executar a rotina preservada do AppSheet. A administração deverá aceitar as decisões pendentes que afetem a operação antes da substituição definitiva.

**Entregável desta etapa:** somente este PRD.md. Não inclui código, banco criado, migração executada, assinatura de serviço ou publicação.

## 22. Ajuste autorizado — cadastro rápido de operadores (29/10/2026)

Esta decisão posterior do responsável atualiza as pendências de inclusão rápida citadas nas seções anteriores:

- Em visitantes, operador pode cadastrar município ausente durante o formulário.
- Em descarte e saída de materiais, operador pode cadastrar veículo ausente, informando placa, condutor e empresa. O cadastro é compartilhado pelos dois módulos.
- Em pessoas a serviço, operador pode cadastrar condutor ausente, informando nome, placa, empresa e veículo.
- Selecionar placa em descarte/retirada sugere condutor e empresa. Selecionar condutor de serviço sugere placa, empresa e veículo.
- Cadastro rápido é preparado no formulário e confirmado em transação junto com a entrada. Cancelar ou falhar não deixa cadastro auxiliar órfão.
- O operador não ganha acesso à edição administrativa, desativação de cadastros, gestão de usuários ou tipos de resíduos/materiais. Cadastros existentes nunca são sobrescritos por inclusão rápida.
