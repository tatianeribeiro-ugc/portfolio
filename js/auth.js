/* ==================================================================================
   AUTENTICAÇÃO COMPARTILHADA (Supabase Auth)
   Este arquivo é carregado em login.html e painel.html, sempre depois do
   <script> do CDN do Supabase. Ele cria o cliente Supabase uma única vez e
   expõe window.Auth com as funções de login, logout e verificação de sessão.
   ================================================================================== */

// EDITE AQUI se precisar trocar de projeto Supabase: URL e chave anon (pública).
// A chave anon é segura para ficar no navegador: o acesso real aos dados é
// controlado pelas policies de Row Level Security configuradas no setup.sql.
const SUPABASE_URL = "https://kjbgifrtaqxtsfbmgoqn.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqYmdpZnJ0YXF4dHNmYm1nb3FuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4MjU4MjEsImV4cCI6MjA5OTQwMTgyMX0.M1-oZuWYiQBPg86UuMTAPo2fygu5kGc3b1th2PZY77M";

// Cliente Supabase, criado uma única vez e reaproveitado em todo o painel.
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

window.Auth = {
  // Dá acesso direto ao cliente Supabase para quem precisar consultar tabelas
  // (usado em painel.html para buscar portfolio_events e portfolio_leads).
  client: sb,

  // Faz login com e-mail e senha. Lança um erro com mensagem amigável em
  // português para o caso mais comum (credenciais erradas).
  async login(email, senha) {
    const { data, error } = await sb.auth.signInWithPassword({ email, password: senha });
    if (error) {
      if (error.message === "Invalid login credentials") {
        throw new Error("E-mail ou senha incorretos.");
      }
      throw new Error(error.message);
    }
    return data.user;
  },

  // Guarda de autenticação: roda no topo de páginas protegidas (painel.html).
  // Se não houver sessão ativa, manda para o login e devolve null.
  async checkAuth() {
    const { data } = await sb.auth.getSession();
    if (!data.session) {
      window.location.href = "login.html";
      return null;
    }
    return data.session.user;
  },

  // Encerra a sessão e volta para o login.
  async logout() {
    await sb.auth.signOut();
    window.location.href = "login.html";
  },

  // Envia o e-mail de redefinição de senha do Supabase Auth.
  async recuperarSenha(email) {
    const { error } = await sb.auth.resetPasswordForEmail(email);
    if (error) throw new Error(error.message);
  }
};
