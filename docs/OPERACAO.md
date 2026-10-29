# Operação e continuidade

## Rotina da portaria

- Inicie em **Registrar Visitantes**. Use **+** para nova entrada.
- Cadastre acompanhantes no formulário do responsável. Eles só são gravados ao salvar o formulário principal.
- **Saída** encerra a movimentação e transfere para o histórico correspondente. Em grupos, todos compartilham a mesma saída.
- A equipe compartilha as movimentações: quem faz a saída pode ser diferente de quem registrou a entrada.
- Use **Atualizar** para consultar mudanças realizadas em outra estação. Não há consulta automática contínua.
- Se houver falha de conexão, mantenha o formulário aberto e verifique o envio pelo mesmo formulário. Não crie outra entrada antes de conferir a primeira.
- Fechar/recarregar o navegador pode perder um rascunho. Não há fila de gravação offline.

## Cadastros e correções

Cadastre primeiro as opções reais usadas pelo PMU, incluindo cidades e os dois conjuntos separados de tipos: resíduos recebidos e materiais retirados. Nome do responsável e placa de visitante são opcionais. Os módulos de serviço, descarte e retirada exigem cadastro de referência.

Quantidade aceita zero e até três casas decimais. Uma placa já aberta gera aviso, não bloqueio. Baixa conjunta, nome opcional e regras de zero seguem as premissas provisórias do PRD e devem ser validadas com Gabriel e os operadores.

Operador pode corrigir dados descritivos de movimentações abertas. Administrador pode corrigir registros encerrados e horários mediante justificativa. Cancelar preserva os dados; não há exclusão definitiva ou reabertura pela interface.

## Senhas e contas

O primeiro código é privado, expira e só pode ser utilizado uma vez. Não há senha padrão. Contas criadas pelo administrador começam com a senha definida por ele; o colaborador pode alterá-la em **Minha senha**.

Desativação bloqueia consultas e gravações imediatamente pelo banco. O último administrador ativo não pode ser desativado ou rebaixado. A recuperação usa a administração, sem envio automático de e-mails ou login Google.

O Supabase pode emitir aviso de proteção contra senhas vazadas desativada. O aplicativo exige 12 caracteres. A disponibilidade e a configuração adicional desse recurso devem ser verificadas no plano do projeto, sem ativar cobrança automaticamente.

## Backup externo

O workflow `.github/workflows/backup.yml` está preparado para execução diária às **03h30 de Brasília**, com retenção de 30 dias. Ele permanece sem execução enquanto a variável `PORTARIA_BACKUP_ENABLED` não for `true`.

Configure, em **GitHub → Settings → Secrets and variables → Actions**:

| Nome | Conteúdo |
|---|---|
| `PORTARIA_DB_HOST` | Host do banco ou **Session Pooler**, conforme a conexão fornecida pelo projeto |
| `PORTARIA_DB_USER` | Usuário dessa conexão; no pooler, normalmente `postgres.<referência>` |
| `PORTARIA_DB_PASSWORD` | Senha de banco, não a chave `anon` nem a senha do aplicativo |
| `PORTARIA_BACKUP_PASSPHRASE` | Frase longa e aleatória, guardada também fora da conta do GitHub |
| variável `PORTARIA_BACKUP_ENABLED` | `true`, somente depois de testar manualmente o workflow |

O dump é enviado por pipe à criptografia, sem arquivo temporário de texto. Cobre os esquemas do produto e autenticação; exclui sessões, tokens de recuperação e logs técnicos de autenticação. Não cobre arquivos de Storage, que não são usados neste MVP. A assinatura HMAC verifica integridade antes da descriptografia; o SHA-256 também detecta corrupção de transporte.

O painel **Continuidade** mostra registros de backup produzidos pelo script. Ausência de registros é pendência, não indicação de que houve uma cópia.

### Restauração

1. Baixe o artefato criptografado, a assinatura `.hmac` e o arquivo `.sha256`. Nunca envie a frase de descriptografia para o repositório ou um chat.
2. Prepare um **banco PostgreSQL 17 isolado e vazio**, compatível com os objetos e papéis do Supabase (`anon`, `authenticated`, `service_role`). Um projeto Supabase vazio já contém objetos de `auth`; nesse caso, um responsável técnico deve planejar a restauração seletiva dos dados de autenticação antes dos dados operacionais. O script genérico não sobrescreve esses objetos.
3. Configure as variáveis `PG*` apontando exclusivamente para o destino isolado e `BACKUP_PASSPHRASE` pelo gerenciador de segredos.
4. Execute `RESTORE_CONFIRM=ISOLATED_DATABASE bash scripts/restore.sh portaria.dump.enc` a partir deste checkout. O script aborta se já houver `app_private` e não usa `--clean`.
5. Aplique/verifique as permissões com `supabase/restore-grants.sql` e execute os cenários SQL. O script desativa qualquer código de bootstrap restaurado e descarta autorizações temporárias de provisionamento.
6. Confira usuários, grupos, acompanhantes, abertos/encerrados, volumes e auditoria. Em um projeto Supabase de teste, publique a Edge Function, aponte uma cópia do frontend para ele e teste Auth e os quatro fluxos.
7. Registre data, responsável, contagens e tempo de recuperação. Só então marque a restauração como validada no controle institucional. Repita trimestralmente.

RPO de 24 horas e RTO de quatro horas úteis são metas do PRD, ainda não demonstradas. Sem as credenciais de conexão e sem exportações do legado, esta entrega não afirma que backup ou migração estejam concluídos.

## Hospedagem, privacidade e custo

A publicação inicial é privada, para teste do responsável. Liberar o acesso da equipe exige definir a audiência na hospedagem ou usar outro serviço compatível com `dist/`.

Nenhum plano pago, domínio ou cobrança foi ativado. Verifique cotas e termos no painel dos provedores. Use o consumo mostrado em **Continuidade** e os relatórios oficiais; estabeleça avisos de 70% e 90% após confirmar as cotas contratadas.

O PMU ainda precisa definir retenção, base e texto informativo, responsabilidade pelas contas e procedimento manual de contingência. O histórico não é excluído após sete dias.
