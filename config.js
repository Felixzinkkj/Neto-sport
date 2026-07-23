// =========================================================
// CONFIGURAÇÃO — preencha com os dados do SEU projeto Supabase
// (Project Settings > API, no painel do Supabase)
// =========================================================
window.NETO_SPORT_CONFIG = {
  SUPABASE_URL: "https://ccmlnozsoqxgywruyxas.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjbWxub3pzb3F4Z3l3cnV5eGFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ3Njg2MDIsImV4cCI6MjEwMDM0NDYwMn0.NEhIhFYCzh550j5bQpLWTaozxM4ElVeHKyGAt2Yu7Ls",
  // Número de WhatsApp que recebe os pedidos (com DDI 55 + DDD + número, só dígitos)
  WHATSAPP_NUMERO: "5584994151129",

  // Link de pagamento parcelado no cartão (opcional). Gere um "Link de
  // pagamento" no Mercado Pago, InfinitePay, PagSeguro ou Stone (permitem
  // escolher o número de parcelas) e cole aqui. Veja o passo a passo no
  // card "Parcelamento no cartão" do admin/dashboard.html.
  LINK_PAGAMENTO_CARTAO: "",
  PARCELAS_MAXIMAS: 12,

  // =========================================================
  // FRETE / ENTREGA
  // Por enquanto a loja só trabalha com retirada na loja (sem
  // cálculo de frete). Este bloco já deixa a estrutura pronta pra
  // quando você quiser ativar o cálculo automático pelos Correios —
  // quando chegar a hora, é só preencher CORREIOS_API_* abaixo e
  // colocar CORREIOS.ATIVO como true. Não precisa mexer em mais nada.
  // =========================================================
  FRETE: {
    // Métodos de entrega que já existem no banco (orders.metodo_frete):
    //   'retirada'      -> retirada na loja, sem custo (único ativo hoje)
    //   'entrega_local' -> entrega própria na sua cidade/região (ainda não usado)
    //   'correios'      -> cálculo automático via API dos Correios (preparado, desativado)
    METODO_PADRAO: "retirada",

    CORREIOS: {
      ATIVO: false, // troque para true quando tiver a API configurada
      CEP_ORIGEM: "", // CEP de onde os produtos saem (obrigatório para o cálculo)
      // Credenciais/contrato da API dos Correios — deixe em branco até ativar.
      // Preencha aqui quando for integrar (ex: usuário e senha do contrato,
      // ou o token do provedor que você escolher usar como intermediário).
      USUARIO: "",
      SENHA: "",
      CONTRATO: "",
    },
  },
};
