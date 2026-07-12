/* ==================================================================================
   RASTREAMENTO DE VISITAS
   Carregado em index.html e videos.html, sempre depois do <script> do CDN do
   Supabase. Grava visitas, cliques e vídeos assistidos no Supabase, para
   aparecerem no painel administrativo (painel.html).

   A chave usada aqui é a anon (pública) e só tem permissão de GRAVAR (insert),
   nunca de ler, editar ou apagar dados. Veja o comentário sobre isso em
   setup.sql, na seção "ESCRITA PÚBLICA".
   ================================================================================== */

(function(){
  // EDITE AQUI se precisar trocar de projeto Supabase (mesmos dados de js/auth.js)
  const SUPABASE_URL = "https://kjbgifrtaqxtsfbmgoqn.supabase.co";
  const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqYmdpZnJ0YXF4dHNmYm1nb3FuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4MjU4MjEsImV4cCI6MjA5OTQwMTgyMX0.M1-oZuWYiQBPg86UuMTAPo2fygu5kGc3b1th2PZY77M";

  const sbRastreio = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // Um id por visita (guardado em sessionStorage: dura enquanto a aba estiver aberta).
  // Não usa nenhum dado pessoal, só serve para contar "visitantes únicos" no painel.
  function obterSessionId(){
    let id = sessionStorage.getItem('portfolio_session_id');
    if(!id){
      id = (window.crypto && window.crypto.randomUUID)
        ? window.crypto.randomUUID()
        : 'sid-' + Date.now() + '-' + Math.random().toString(16).slice(2);
      sessionStorage.setItem('portfolio_session_id', id);
    }
    return id;
  }

  // Grava um evento. Silenciosa em caso de falha (nunca deve atrapalhar a
  // navegação de quem está visitando o site).
  function registrarEvento(eventType, eventName, metadata){
    sbRastreio.from('portfolio_events').insert({
      event_type: eventType,
      event_name: eventName || null,
      session_id: obterSessionId(),
      page_path: window.location.pathname,
      metadata: metadata || null
    }).then(({ error }) => {
      if(error) console.warn('Rastreio: falha ao gravar evento.', error.message);
    });
  }

  function registrarLead(dados){
    return sbRastreio.from('portfolio_leads').insert({
      name: dados.name || null,
      email: dados.email || null,
      phone: dados.phone || null,
      brand: dados.brand || null,
      budget: dados.budget || null,
      message: dados.message || null,
      source: dados.source || 'contact'
    });
  }

  // API usada pelo restante da página (index.html e videos.html).
  window.Rastreio = {
    buttonClick(nome, metadata){ registrarEvento('button_click', nome, metadata); },
    videoView(youtubeId, titulo){ registrarEvento('video_view', youtubeId, titulo ? { title: titulo } : null); },
    lead(dados){ return registrarLead(dados); }
  };

  // Registra a visita automaticamente, assim que este script carrega.
  registrarEvento('page_view', document.title);
})();
