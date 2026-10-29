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
- Formulário mantido em memória em falhas de conexão ou expiração de sessão. Não grava offline nem mantém dados pessoais em cache de PWA.
- Lançamentos de contingência pela administração com horário ocorrido e justificativa.
- Importação canônica com simulação, identificação do legado e prevenção de duplicatas.

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
- `scripts/integration-http.mjs`: teste contra ambiente preparado; credenciais temporárias por stdin. **Não executar em produção sem um ambiente de teste separado**.
- `/qa` e `mobile-preview.html`: teste visual em `vite dev`, exclusivamente com dados fictícios em memória. Não integram a versão de produção; não acessam o banco real.

Consulte [operação e backups](docs/OPERACAO.md), [migração](docs/MIGRACAO.md) e [validação desta entrega](docs/VALIDACAO.md).

## Antes de substituir o AppSheet

Importar e conciliar as exportações reais; homologar os quatro fluxos com a equipe; configurar backup externo, ensaiar restauração e definir responsáveis institucionais por acesso, retenção e contingência. Não foram recebidas exportações das tabelas reais e nenhum histórico foi inventado.

## Identidade visual

Brasão obtido no portal oficial da Prefeitura, página “Símbolos Oficiais”:
https://www.riodasostras.rj.gov.br/simbolos-oficiais/

O arquivo foi reduzido mantendo proporções para uso no aplicativo. A administração deve validar a aplicação da identidade institucional.
