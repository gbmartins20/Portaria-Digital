# Portaria Digital · PMU

Aplicativo web do Parque Municipal Roberto Pereira Inocêncio (Roberto Cação), Rio das Ostras/RJ. Implementa os quatro módulos e a rotina de grupos descritos em [PRD.md](PRD.md).

## Acesso inicial

1. Abra o endereço da aplicação e escolha **Configurar primeiro acesso**.
2. Informe seu nome, e-mail, uma senha com pelo menos 12 caracteres e o código de uso único entregue em particular. O código expira após sete dias e não está neste repositório.
3. Em **Cadastros auxiliares**, cadastre as cidades, empresas, veículos, condutores e tipos realmente usados pelo PMU.
4. Em **Equipe e permissões**, crie uma conta individual para cada colaborador.

Não existe cadastro público. Recuperação de senha é feita pela administração no menu de equipe; cada usuário também pode trocar sua própria senha.

## Funcionalidades

- Registrar Visitantes, Descarte, Saída de Materiais e Pessoas à Serviços, na mesma ordem do legado.
- Uma visita contém um responsável e seus acompanhantes. Salvar e registrar saída são operações transacionais do grupo inteiro.
- Pesquisa no servidor, paginação, históricos, filtros por dia de Brasília e detalhe dos integrantes.
- Cadastro rápido de municípios, veículos e condutores pelo operador, dentro do atendimento e confirmado junto com a entrada.
- Cadastros auxiliares, preenchimento assistido e preservação da empresa/condutor/cidade históricos.
- Perfis de operador e administrador. Conta desativada perde acesso mesmo com token emitido anteriormente.
- Correções com controle de versão, cancelamento com motivo, trilha de auditoria e CSV administrativo protegido contra fórmulas.
- Reenvios idempotentes e baixa concorrente sem substituir horário ou operador originais.
- Entradas e saídas offline persistidas em IndexedDB por conta, fila com sincronização autenticada e idempotente, horários do aparelho auditados e shell PWA em service worker. Correções e administração exigem internet.
- Lançamentos de contingência pela administração com horário ocorrido e justificativa.
- Importação canônica com simulação, identificação do legado e prevenção de duplicatas.
- Importação da exportação Excel original com arquivo privado de todas as linhas, conciliação dos grupos e consulta de históricos incompletos sem inventar datas ou quantidades.

## Desenvolvimento

Node.js 22 ou superior; Node 24 utilizado na validação.

```sh
npm ci
npm run dev
npm test
npm run build
```

O cliente já aponta para `nnwuxnwjbprybyjslaob`. `.env.example` documenta as duas configurações **públicas** que podem substituir esse endereço e sua chave publicável. Nenhuma chave administrativa é enviada ao navegador.

A aplicação é estática; `dist/` pode ser hospedado em um serviço HTTPS compatível. O deploy desta entrega utiliza Sites em acesso privado para o piloto. O código permanece neste repositório e não depende do provedor de hospedagem para operar com Supabase.

## Banco e API

Migrações em `supabase/migrations/`. Dados em `app_private`, com RLS e bloqueio de acesso direto. A Data API expõe funções invoker; implementações privilegiadas ficam no esquema privado, com autorização explícita por conta ativa e perfil.

`supabase/functions/portaria-admin/` gerencia contas e primeiro acesso. A verificação de JWT da plataforma fica desativada **somente porque a função valida autenticação internamente**, e a configuração inicial exige código secreto de uso único. As credenciais administrativas são variáveis protegidas do próprio Supabase.

Não recrie o banco nem execute migrações novamente sobre o projeto desta entrega: elas já foram aplicadas. Para outro projeto, use a CLI e as migrações versionadas, revise `restore-grants.sql` e publique a Edge Function. Não copie o código de configuração entre ambientes.

## Testes e operação

- `npm test`: validação de decimais, placas, horário brasileiro, permanência e CSV.
- `tests/sql/integrity.sql`: cenários transacionais e de autorização, em transação revertida.
- `python -m unittest tests/workbook_test.py` e `tests/sql/workbook.sql`: datas do Excel, campos históricos ausentes, idempotência, proteção do arquivo e conciliação.
- `scripts/integration-http.mjs`: teste contra ambiente preparado; credenciais temporárias por stdin. **Não executar em produção sem um ambiente de teste separado**.
- `/qa` e `mobile-preview.html`: teste visual em `vite dev`, exclusivamente com dados fictícios em memória. Não integram a versão de produção; não acessam o banco real.

Consulte [operação e backups](docs/OPERACAO.md), [migração](docs/MIGRACAO.md) e [validação desta entrega](docs/VALIDACAO.md).

## Antes de substituir o AppSheet

Conferir as pendências identificadas no legado; homologar os quatro fluxos com a equipe; configurar backup externo, ensaiar restauração e definir responsáveis institucionais por acesso, retenção e contingência. O manifesto privado de importação registra os totais e o resultado da conciliação. Campos ausentes do arquivo não são inventados.

## Identidade visual

Brasão obtido no portal oficial da Prefeitura, página “Símbolos Oficiais”:
https://www.riodasostras.rj.gov.br/simbolos-oficiais/

O arquivo foi reduzido mantendo proporções para uso no aplicativo. A administração deve validar a aplicação da identidade institucional.

## Perfil e notificações

No menu lateral, **Configurações** permite trocar ou remover a foto e alterar a própria senha (12 a 128 caracteres, com confirmação). A saudação usa o nome do perfil; sem foto, mostra o ícone de usuário. As fotos são ajustadas para 512 × 512, guardadas em bucket privado e acessíveis apenas ao titular.

Administradores podem ativar alertas e escolher Visitantes, Descarte, Saída de materiais e Pessoas a serviço. A preferência começa desligada e é individual. Ao salvar com os alertas ativados, o navegador pede permissão e registra este aparelho. Repita em cada aparelho que receberá alertas. No iPhone, abra o aplicativo instalado na Tela de Início. Desativar a preferência interrompe os alertas em todos os aparelhos; o botão de desativação do aparelho e o logout removem a inscrição local.

Novas entradas online são persistidas primeiro no IndexedDB e enviadas por `portaria-notifications` → `pd_save_online`. A função salva o registro e cria um evento idempotente na mesma transação. O envio Web Push ocorre em segundo plano, com destinatários e permissões conferidos no servidor, validade de 60 segundos e sem retentativa acumulada. Nenhum dado pessoal de visitantes aparece na notificação. Ao tocar no alerta, o aplicativo abre o registro após autenticar.

A fila offline continua usando `pd_sync`, que não cria eventos. Queda de conexão, recarga da página e reenvio da mesma chave preservam o registro sem gerar eventos duplicados. Edições, saídas e lançamentos com horário corrigido também são silenciosos. Não se altera a fila de pendências existente.

### Ordem de publicação desta funcionalidade

1. Aplicar `supabase/migrations/20261105172555_profile_settings_push.sql` e executar `tests/sql/profile-settings-push.sql` (transação revertida no final).
2. Publicar a Edge Function `portaria-notifications`, incluindo `validation.ts`. `verify_jwt=false` é intencional: a função valida cada token com `auth.getUser` e usa o JWT do usuário nas operações de registro.
3. Publicar o frontend na Vercel. Não publicar o frontend antes do backend.
4. Ativar notificações em uma conta administradora e verificar entrega em aparelho real. Chaves VAPID são geradas no servidor ao configurar o primeiro aparelho e guardadas somente no schema privado; não há segredo adicional no frontend.

Testes: `npm test`, `npm run build` e `tests/sql/profile-settings-push.sql`. Este último verifica permissões das fotos, isolamento de contas, preferências, quatro categorias, idempotência, expiração, revogação e ausência de alertas para sincronização e saída.
