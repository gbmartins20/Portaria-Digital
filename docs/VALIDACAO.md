# Validação da implementação · 29/10/2026

## Executado

- Build de produção com TypeScript estrito e Vite; nenhuma dependência de Google/AppSheet.
- Sete testes de domínio e proteção de backup: placa, decimal, CSV, passagem pela meia-noite, dia de Brasília contagem de grupo na exportação e assinatura de backup com rejeição de adulteração/senha incorreta.
- Testes SQL em transação revertida, com identidades sintéticas: grupo com três acompanhantes, falha integral, reenvio, versão de edição, baixa idempotente, históricos, autorização, decimal, zero, negativos/NaN, fotografia histórica e cancelamento.
- Cinco cenários adicionais de importação: simulação sem persistência, aplicação, reexecução sem duplicação, contagem e bloqueio de projeção não conciliada.
- 28 verificações pela API real do projeto: primeiro acesso, login, gestão de operador, chamadas anônimas, reuso de código, grupos, duas entradas simultâneas com a mesma chave, duas baixas simultâneas, tipos/decimais, bloqueio administrativo e desativação com token ainda emitido.
- Inspeção visual no navegador da tela de login e dos módulos, com dados fictícios em memória para o teste de interface. Cadastro de responsável + acompanhante, retorno ao formulário, salvamento, baixa e histórico.
- Inspeção da interface em quadro de 360 × 800 px. O teste visual usa `/qa` somente em desenvolvimento; os fluxos de servidor são testados separadamente contra a API real.
- Auditoria das dependências de produção: nenhuma vulnerabilidade reportada.
- Revisão de acesso: tabelas no esquema privado, RLS, bloqueio direto, funções privilegiadas privadas e nenhum segredo administrativo no bundle.
- A compilação de produção exclui os dados e a rota funcional do teste visual.

## Limites de homologação

Não foram disponibilizadas exportações reais, credenciais de banco para backup externo, nem os aparelhos efetivamente usados pela equipe. Não foi realizada conciliação do legado, restauração completa de um dump externo, teste de 100 mil registros/10 operadores ou medição de P95 em condições equivalentes às da portaria.

O fluxo inicial foi implementado com as premissas do PRD: nome de visitante opcional, zero permitido nos volumes, baixa conjunta e ausência de serviço a pé sem placa fictícia. Essas decisões exigem homologação operacional, junto com cores e aplicação do brasão.

O aplicativo é entregue para piloto do responsável. A substituição definitiva do AppSheet depende dos critérios de pronto do PRD, especialmente migração, backup restaurado, equipe e responsabilidades institucionais.

## Ajustes de cadastro rápido · 29/10/2026

- Nove testes locais aprovados, incluindo o preenchimento por placa em descarte/retirada e por condutor em serviço, sem herdar dados da carga anterior.
- `tests/sql/quick-catalogs.sql` validou inclusão pelo operador nos quatro módulos, reutilização do veículo entre descarte e retirada, reenvio sem duplicatas, rejeição de cadastro existente com outros dados, rollback integral e bloqueio de conta inativa/gestão administrativa indevida. Todos os dados de teste foram revertidos.
- Interface verificada no navegador com perfil de operador e dados fictícios: município novo selecionado na visita; veículo cadastrado no descarte e reutilizado na retirada com condutor/empresa preenchidos; novo condutor de serviço cadastrado e depois selecionado com placa, empresa e veículo preenchidos.
- Cancelar o formulário preserva o comportamento de descarte do rascunho; nenhum cadastro rápido é gravado separadamente da movimentação.
