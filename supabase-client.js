// =========================================================
// Cliente Supabase compartilhado por todas as páginas.
// Requer que config.js seja carregado ANTES deste arquivo,
// e o script da CDN do supabase-js também antes deste arquivo:
//
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
// <script src="config.js"></script>
// <script src="supabase-client.js"></script>
// =========================================================

const { SUPABASE_URL, SUPABASE_ANON_KEY } = window.NETO_SPORT_CONFIG;

window.supa = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ---------- Segurança: escapar texto antes de inserir em HTML ----------
// Nomes de produto, descrições, nome do cliente etc. vêm do banco e podem
// ter sido digitados por qualquer conta com acesso de admin/atendente (ou,
// no caso do nome do cliente, até por engano/má-fé de alguém no balcão).
// Sempre passe texto dinâmico por aqui antes de inserir com innerHTML,
// para impedir que uma tag <script> ou <img onerror=...> vire código
// executado na tela de outra pessoa (ataque XSS).
function escapeHtml(texto) {
  if (texto === null || texto === undefined) return '';
  return String(texto)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ---------- Helpers de formatação ----------
function formatarPreco(centavos) {
  return (centavos / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

function formatarData(data) {
  return new Date(data).toLocaleString('pt-BR');
}

const STATUS_LABEL = {
  pendente: 'Pendente', pago: 'Pago', em_preparo: 'Em preparo',
  enviado: 'Enviado', entregue: 'Entregue', cancelado: 'Cancelado', estornado: 'Estornado'
};

// ---------- Helpers de autenticação ----------
async function getUsuarioLogado() {
  const { data } = await window.supa.auth.getUser();
  return data?.user || null;
}

async function getPerfil(userId) {
  const { data, error } = await window.supa
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();
  if (error) return null;
  return data;
}

async function fazerLogout() {
  await window.supa.auth.signOut();
  window.location.href = 'index.html';
}

// Confere se o usuário logado é admin e/ou funcionário. Usado para
// liberar as telas de admin/produtos.html, admin/dashboard.html e
// atendente/painel.html.
async function verificarAcesso({ exigirAdmin = false } = {}) {
  const user = await getUsuarioLogado();
  if (!user) return { ok: false, motivo: 'Você precisa estar logado. Volte para a loja e faça login.' };
  const perfil = await getPerfil(user.id);
  const liberado = exigirAdmin ? !!perfil?.is_admin : !!(perfil?.is_admin || perfil?.is_funcionario);
  if (!liberado) return { ok: false, motivo: 'Sua conta não tem permissão de acesso a esta página.' };
  return { ok: true, user, perfil };
}

// ---------- Cliques em "Finalizar no WhatsApp" ----------
async function registrarCliqueWhatsapp(orderId, userId) {
  try {
    await window.supa.from('whatsapp_clicks').insert({ order_id: orderId || null, user_id: userId });
  } catch (e) { console.warn('Não foi possível registrar o clique do WhatsApp', e); }
}

// ---------- Dar baixa em um pedido (marcar como pago + baixar estoque) ----------
// Idempotente: se o pedido já não estiver "pendente", só troca o status
// sem mexer no estoque de novo.
async function darBaixaPedido(orderId) {
  const { data: pedido, error: errPedido } = await window.supa
    .from('orders').select('*, order_items(*)').eq('id', orderId).single();
  if (errPedido) return { error: errPedido };

  const eraPendente = pedido.status === 'pendente';

  const { error: errUpdate } = await window.supa
    .from('orders').update({ status: 'pago' }).eq('id', orderId);
  if (errUpdate) return { error: errUpdate };

  if (eraPendente) {
    for (const item of pedido.order_items) {
      if (!item.product_id) continue;
      const { data: produto } = await window.supa
        .from('products').select('estoque').eq('id', item.product_id).single();
      if (!produto) continue;
      const novoEstoque = Math.max(0, produto.estoque - item.quantidade);
      await window.supa.from('products').update({ estoque: novoEstoque }).eq('id', item.product_id);
    }
  }
  return { error: null };
}

// ---------- Cancelar um pedido pendente (cliente desistiu da compra) ----------
// Só cancela pedidos que ainda estão "pendente" (não mexe em estoque, pois
// a baixa no estoque só acontece quando o pedido é pago).
async function cancelarPedido(orderId) {
  const { error } = await window.supa
    .from('orders')
    .update({ status: 'cancelado' })
    .eq('id', orderId)
    .eq('status', 'pendente');
  return { error };
}

// ---------- Reiniciar todas as operações (zera o dashboard) ----------
// Apaga todo o histórico de pedidos, itens de pedido e cliques no WhatsApp.
// NÃO mexe em produtos, categorias nem contas de usuário — só no histórico
// de vendas/operações. Ação irreversível, só deve ser chamada depois de uma
// confirmação clara do admin.
async function reiniciarOperacoes() {
  const semFiltro = { criado_em: '1900-01-01T00:00:00Z' };
  const { error: errItens } = await window.supa
    .from('order_items').delete().gte('id', '00000000-0000-0000-0000-000000000000');
  if (errItens) return { error: errItens };

  const { error: errPedidos } = await window.supa
    .from('orders').delete().gte('criado_em', semFiltro.criado_em);
  if (errPedidos) return { error: errPedidos };

  const { error: errCliques } = await window.supa
    .from('whatsapp_clicks').delete().gte('criado_em', semFiltro.criado_em);
  if (errCliques) return { error: errCliques };

  return { error: null };
}

// ---------- Helpers de carrinho (localStorage até o checkout) ----------
const CART_KEY = 'neto_sport_carrinho';

function getCarrinho() {
  try {
    return JSON.parse(localStorage.getItem(CART_KEY)) || [];
  } catch {
    return [];
  }
}

function salvarCarrinho(itens) {
  localStorage.setItem(CART_KEY, JSON.stringify(itens));
  atualizarContadorCarrinho();
}

function adicionarAoCarrinho(produto, tamanho, quantidade = 1) {
  const itens = getCarrinho();
  const existente = itens.find(i => i.product_id === produto.id && i.tamanho === tamanho);
  if (existente) {
    existente.quantidade += quantidade;
  } else {
    itens.push({
      product_id: produto.id,
      nome: produto.nome,
      preco_centavos: produto.preco_promocional_centavos || produto.preco_centavos,
      imagem_url: produto.imagem_url,
      tamanho: tamanho || null,
      quantidade
    });
  }
  salvarCarrinho(itens);
}

function removerDoCarrinho(index) {
  const itens = getCarrinho();
  itens.splice(index, 1);
  salvarCarrinho(itens);
}

function totalCarrinhoCentavos() {
  return getCarrinho().reduce((soma, i) => soma + i.preco_centavos * i.quantidade, 0);
}

function atualizarContadorCarrinho() {
  const el = document.querySelectorAll('[data-cart-count]');
  const total = getCarrinho().reduce((s, i) => s + i.quantidade, 0);
  el.forEach(e => e.textContent = total);
}

document.addEventListener('DOMContentLoaded', atualizarContadorCarrinho);

// ---------- Frete ----------
// Ponto único de cálculo de frete. Hoje só existe 'retirada' (sem custo).
// Quando 'entrega_local' ou 'correios' forem ativados em config.js, é só
// completar os ramos correspondentes aqui — nada no checkout (loja.html)
// precisa mudar, porque ele só chama esta função e usa o resultado.
//
// Retorna: { frete_centavos, prazo_dias, erro }
async function calcularFrete(metodo, endereco) {
  const cfg = window.NETO_SPORT_CONFIG.FRETE || {};

  if (metodo === 'retirada') {
    return { frete_centavos: 0, prazo_dias: null, erro: null };
  }

  if (metodo === 'entrega_local') {
    // Ainda não ativado. Quando for usar entrega própria na região,
    // defina aqui uma taxa fixa (ou uma tabela por bairro/cidade).
    return { frete_centavos: null, prazo_dias: null, erro: 'Entrega local ainda não está disponível.' };
  }

  if (metodo === 'correios') {
    if (!cfg.CORREIOS || !cfg.CORREIOS.ATIVO) {
      return { frete_centavos: null, prazo_dias: null, erro: 'Frete pelos Correios ainda não está disponível.' };
    }
    if (!endereco || !endereco.cep) {
      return { frete_centavos: null, prazo_dias: null, erro: 'Informe o CEP de entrega para calcular o frete.' };
    }
    // TODO (quando ativar): chamar aqui a API dos Correios (ou um provedor
    // intermediário, ex: SuperFrete/Melhor Envio) usando cfg.CORREIOS.CEP_ORIGEM
    // como origem e endereco.cep como destino, junto com peso/dimensões dos
    // itens do carrinho. Retornar o valor calculado em frete_centavos e o
    // prazo em prazo_dias. Até lá, este ramo fica com um erro amigável.
    return { frete_centavos: null, prazo_dias: null, erro: 'Integração com os Correios ainda não foi implementada.' };
  }

  return { frete_centavos: null, prazo_dias: null, erro: 'Método de frete desconhecido.' };
}
