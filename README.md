# Neto Sport — Sistema próprio (Supabase + checkout via WhatsApp)

Este pacote substitui o checkout do Shopify por um sistema próprio:
banco de dados, login de clientes, catálogo com categorias, carrinho,
importação de produtos por CSV e um dashboard de vendas. O pagamento é
combinado direto pelo **WhatsApp**: o cliente monta o carrinho no site,
clica em "Finalizar compra" e é levado ao WhatsApp com o resumo do
pedido já escrito, pronto pra você combinar o Pix (ou qualquer forma de
pagamento) e confirmar a venda manualmente.

**A página inicial (`index.html`) continua exatamente como era antes** —
mesmo visual, mesmas animações. A única mudança nela é que o botão
**"Conheça Nossa Loja"** agora leva para `loja.html` em vez do link do Shopify.

## O que tem aqui

```
index.html                 → site institucional original (sem alterações, exceto o botão da loja)
loja.html                  → página de vendas: produtos + categorias do banco, carrinho, login, checkout
admin/produtos.html        → cadastro, edição de estoque e EXCLUSÃO de produtos (só admin)
admin/dashboard.html       → dashboard de vendas, cliques no WhatsApp e "dar baixa" em pedidos (só admin)
atendente/painel.html      → painel simples para funcionários (venda de balcão, dar baixa, produtos)
config.js                  → chaves do Supabase, número de WhatsApp e link de pagamento parcelado
supabase-client.js         → funções compartilhadas (carrinho, auth, dar baixa, etc.)
supabase/schema.sql        → banco de dados completo (rodar 1x no Supabase)
modelo-produtos.csv        → modelo de planilha para importar produtos (já com coluna de categoria)
```

## ⚠️ Se você já tinha esse site rodando (atualização)
Esta versão adicionou permissões novas no banco de dados (para o botão
"Reiniciar todas as operações" funcionar). **Você precisa rodar o
`supabase/schema.sql` de novo** no SQL Editor do Supabase — é seguro rodar
de novo, ele só cria o que ainda não existe e atualiza políticas. Sem esse
passo, o botão de reiniciar vai dar erro de permissão.

## Frete e entrega
Hoje a loja trabalha só com **retirada na loja** (sem cálculo de frete) —
foi assim que você decidiu por enquanto. Mas o terreno já está preparado
para quando você quiser ativar entrega:

- O banco (`supabase/schema.sql`) já tem uma tabela `addresses` e as colunas
  `orders.metodo_frete` e `orders.frete_centavos`, prontas mas sem uso hoje.
- `config.js` tem um bloco `FRETE` com `CORREIOS.ATIVO: false` — é aqui que
  entram as credenciais/contrato quando for a hora.
- `supabase-client.js` tem uma função `calcularFrete(metodo, endereco)` —
  é o único lugar que decide o valor do frete. O checkout (`loja.html`) já
  chama essa função, então **quando você pedir para eu ativar os Correios,
  eu só preciso preencher essa função e o bloco `FRETE.CORREIOS` do
  `config.js`** — não precisa reescrever o checkout, o banco ou o dashboard.
- `admin/dashboard.html` já mostra a coluna "Entrega" na tabela de pedidos
  (hoje sempre "Retirada").

Quando você quiser expandir para o Brasil todo pelos Correios, é só me
avisar — nessa hora eu adiciono o formulário de endereço no checkout e
plugo a chamada real da API no lugar já preparado.

## Novidades desta versão
- **Estatística de pedidos cancelados**: o `admin/dashboard.html` agora
  mostra um KPI **"Pedidos cancelados"** (soma pedidos cancelados e
  estornados), ao lado dos outros números.
- **Segurança contra XSS**: nome, descrição e outros textos de produtos,
  categorias e clientes agora passam por uma função de escape (`escapeHtml`
  em `supabase-client.js`) antes de aparecer na tela. Antes, um nome de
  produto ou nome de cliente com código HTML/JavaScript embutido (ex:
  `<script>`) poderia rodar na tela de quem visualizasse essa informação —
  agora isso é neutralizado em todas as telas (loja, admin de produtos,
  dashboard e painel do atendente).
- **Grade de produtos quadrada**: em `loja.html`, os cards de produto agora
  usam imagem quadrada (1:1) e a grade fica fixa em 5 colunas em telas
  grandes, reduzindo para 4/3/2/1 conforme a tela fica menor.
- **Reiniciar todas as operações**: no `admin/dashboard.html`, dentro do
  card "⚠️ Zona de risco", tem um botão **"Reiniciar todas as operações"**
  que apaga todo o histórico de pedidos, vendas e cliques no WhatsApp,
  zerando todos os números do dashboard. Produtos, estoque e contas de
  usuário/atendente **não são apagados** — só o histórico de vendas. Pede
  para digitar `REINICIAR` antes de confirmar, já que não pode ser
  desfeito. Só aparece para admin (a página inteira já é restrita a admin).
- **Cancelar pedido**: tanto no `admin/dashboard.html` (tabela "Últimos
  pedidos") quanto no `atendente/painel.html` (aba "Pedidos pendentes"),
  todo pedido pendente agora tem, ao lado do botão "Dar baixa", um botão
  **"Cancelar"** — use quando o cliente desistir da compra. O pedido vai
  para o status "Cancelado" e não mexe no estoque (a baixa no estoque só
  acontece quando o pedido é dado como pago).
- **Excluir produtos**: em `admin/produtos.html` agora tem uma lista de todos os
  produtos cadastrados, com edição de estoque direto na tabela, botão para
  ativar/desativar e botão **Excluir** (some da loja definitivamente).
- **Contador de cliques no WhatsApp**: toda vez que um cliente clica em
  "Finalizar compra" e é levado ao WhatsApp, isso é registrado. O
  `admin/dashboard.html` mostra o total de cliques, quantos foram hoje, e a
  **taxa de conversão** (quantos desses cliques viraram pedido pago).
- **Dar baixa em 1 clique**: tanto no dashboard quanto no painel do atendente,
  todo pedido pendente tem um botão **"Dar baixa"** que marca como pago e já
  desconta o estoque automaticamente — sem precisar abrir o Supabase.
- **Parcelamento no cartão pelo WhatsApp**: veja a seção
  [Parcelamento no cartão](#parcelamento-no-cartão-de-crédito-pelo-whatsapp)
  abaixo.
- **Painel do Atendente** (`atendente/painel.html`): uma tela separada e bem
  simples para os funcionários, sem acesso ao faturamento nem às outras telas
  de admin. Veja a seção [Painel do atendente](#painel-do-atendente) abaixo.

## Passo a passo

### 1. Criar o projeto no Supabase
1. Crie uma conta em https://supabase.com e crie um novo projeto.
2. Em **Project Settings > API**, copie a **Project URL** e a **anon public key**.
3. Cole essas duas informações no arquivo `config.js`.

### 2. Colocar seu número de WhatsApp
No `config.js`, edite `WHATSAPP_NUMERO` com o número que vai receber os
pedidos: DDI 55 + DDD + número, só dígitos (ex: `5584994151129`).

### 3. Rodar o banco de dados
1. No painel do Supabase, abra **SQL Editor > New query**.
2. Cole todo o conteúdo de `supabase/schema.sql` e clique em **Run**.
   Isso cria as tabelas de produtos, pedidos, perfis, e já configura as
   regras de segurança (RLS) — clientes só veem/editam os próprios dados,
   só administradores cadastram produtos.

### 4. Desligar a confirmação por e-mail (recomendado)
Por padrão o Supabase exige que o cliente confirme o cadastro por e-mail
antes de conseguir comprar, e o plano gratuito tem um limite baixo de
e-mails por hora. Pra evitar dor de cabeça:
1. No painel do Supabase, vá em **Authentication > Sign In / Providers > Email**.
2. Desligue **"Confirm email"**.
3. Ainda em Authentication, confirme em **Settings** que "Allow new users
   to sign up" está ligado.

### 5. Criar seu usuário admin
1. Abra `loja.html` no navegador (ou já hospedado) e crie uma conta normal
   pela loja ("Minha conta > Criar conta").
2. No Supabase, vá em **SQL Editor** e rode (trocando pelo seu e-mail):
   ```sql
   update public.profiles set is_admin = true
   where id = (select id from auth.users where email = 'seuemail@exemplo.com');
   ```
3. Faça login de novo em `loja.html` — o link **Admin** vai aparecer no menu.

### 5.1. Criar contas de funcionário (opcional)
Para dar acesso ao **Painel do Atendente** para alguém sem torná-lo admin
(ele não verá faturamento nem as telas de admin, só o próprio painel):
1. Peça para a pessoa criar uma conta normal em `loja.html` ("Minha conta > Criar conta").
2. No Supabase, vá em **SQL Editor** e rode (trocando pelo e-mail dela):
   ```sql
   update public.profiles set is_funcionario = true
   where id = (select id from auth.users where email = 'funcionario@exemplo.com');
   ```
3. A pessoa faz login em `loja.html` e o link **"Painel do atendente"** aparece
   no menu, levando para `atendente/painel.html`.

### 6. Publicar o site
Qualquer hospedagem de arquivos estáticos serve (Vercel, Netlify, Cloudflare
Pages, ou até um servidor simples). Basta subir a pasta inteira (menos a
pasta `supabase/`, que fica só no Supabase).

### 7. Importar seus produtos
1. Acesse `admin/produtos.html` logado como admin.
2. Preencha uma planilha no formato de `modelo-produtos.csv` (pode editar
   esse arquivo direto no Excel/Google Sheets e exportar como CSV).
3. Arraste o arquivo na tela — o sistema mostra uma prévia antes de importar.
4. Clique em **Confirmar importação**.

### 8. Acompanhar as vendas
Acesse `admin/dashboard.html` (logado como admin) para ver faturamento,
pedidos por status, produtos mais vendidos e os últimos pedidos.

## Como funciona o checkout
1. O cliente monta o carrinho e clica em **"Finalizar compra"**.
2. O pedido é salvo no banco com status `pendente`.
3. O WhatsApp abre automaticamente (seu número, definido em `config.js`)
   já com uma mensagem pronta listando os produtos, tamanhos e o total.
4. Você combina o pagamento (Pix, cartão parcelado pelo link, o que
   preferir) direto na conversa.
5. Depois de confirmar o pagamento, clique em **"Dar baixa"** no
   `admin/dashboard.html` (ou no `atendente/painel.html`, aba "Pedidos
   pendentes") — o pedido vira `pago` e o estoque é descontado automaticamente.

## Parcelamento no cartão de crédito pelo WhatsApp
Como hoje o pagamento é combinado manualmente na conversa (sem um gateway
integrado), a forma mais simples e segura de aceitar cartão parcelado é usar
um **"Link de pagamento"** de um provedor pronto — o cliente escolhe o
número de parcelas na hora de pagar, direto no link, e o dinheiro cai na sua
conta. Passo a passo:

1. Crie uma conta grátis em um destes serviços (todos brasileiros, com Pix e
   cartão parcelado): [Mercado Pago — Link de pagamento](https://www.mercadopago.com.br/tools/link-de-pagamento),
   [InfinitePay](https://www.infinitepay.io) ou [PagSeguro](https://pagseguro.uol.com.br).
2. No painel deles, gere um **link de pagamento** avulso, com a opção de
   parcelamento no cartão ativada (normalmente até 12x, com juros definidos
   pelo próprio provedor).
3. Cole esse link no `config.js`, no campo `LINK_PAGAMENTO_CARTAO`.
4. Pronto — a partir daí, toda mensagem de checkout que abre no WhatsApp já
   inclui automaticamente uma linha oferecendo o pagamento parcelado com
   esse link. Você também vê o link configurado no card "Parcelamento no
   cartão de crédito pelo WhatsApp" dentro do `admin/dashboard.html`.

No **Painel do Atendente**, ao registrar uma venda de balcão, o atendente
pode escolher a forma de pagamento **"Cartão de crédito parcelado"** e
informar o número de parcelas — isso fica registrado no pedido para
controle, mas a cobrança em si (se for por link ou na maquininha da loja)
continua sendo feita fora do sistema, do jeito que vocês já usam hoje.

## Painel do atendente
`atendente/painel.html` foi feito para ser usado por qualquer funcionário,
sem exigir nenhum conhecimento técnico. Ele tem 4 abas bem grandes:

- **Nova venda**: busca o produto pelo nome, adiciona na lista, escolhe a
  forma de pagamento e clica em "Finalizar venda". Pronto — o pedido já
  nasce marcado como pago (ou pendente, se for "a combinar pelo WhatsApp")
  e o estoque é descontado na hora.
- **Pedidos pendentes**: mostra os pedidos feitos pelos clientes na loja
  (via WhatsApp) que ainda não foram confirmados. Um clique em
  **"Dar baixa"** marca como pago.
- **Minhas vendas**: histórico das vendas que aquele atendente registrou.
- **Produtos**: cadastro rápido de produto novo + lista com exclusão.

Um funcionário só vê esse painel — ele não tem acesso ao faturamento nem
às outras telas de `admin/`.

## Limitações a saber
- O upload de imagem de produto é feito por **URL** (ex: hospede as fotos no
  Supabase Storage, ou em qualquer CDN de imagens). Se quiser, posso adicionar
  depois um upload direto de arquivo pela tela de admin.
- O design de `loja.html` é uma base funcional com a identidade visual
  (preto/amarelo, tipografia) do site original, mas mais simples — sem as
  animações da página inicial. Posso deixar mais parecido visualmente se quiser.
- Frete não está calculado automaticamente — hoje o pedido soma só o valor
  dos produtos. Posso adicionar uma tabela de frete fixo ou integração com
  correios/transportadora depois, se for do seu interesse.
- Confirmar o pagamento hoje é manual (você ou o atendente clica em
  "Dar baixa" depois que o cliente paga). Se no futuro quiser automatizar
  isso com Pix de verdade (QR Code + confirmação automática) ou com
  cobrança de cartão parcelado direto pela API do provedor (sem precisar
  colar link nenhum), é só pedir.
