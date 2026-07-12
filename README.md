# Painel administrativo

Painel de números do portfólio (visitas, cliques, vídeos vistos e mensagens),
protegido por login. HTML, CSS e JavaScript puro, sem build e sem Node. Os
dados vêm do Supabase, carregado por CDN.

## Passo a passo

1. **Rode o `setup.sql` no Supabase.** No painel do Supabase, vá em *SQL
   Editor* → *New query*, cole o conteúdo de `setup.sql` e clique em *Run*.
   Isso cria as tabelas `portfolio_events` e `portfolio_leads` e liga a
   segurança (RLS).

2. **Crie seu usuário de login.** No painel do Supabase, vá em
   *Authentication* → *Users* → *Add user*, digite seu e-mail e uma senha.
   Esse é o login que você vai usar em `login.html`.

3. **Teste localmente.** Abra `login.html` com duplo clique (ou publique
   antes, veja o passo 5) e entre com o e-mail e a senha do passo 2. Você
   deve cair em `painel.html` já com os números (mesmo que zerados, se ainda
   não houver dados nas tabelas).

4. **Confirme que o "Sair" funciona.** No rodapé da barra lateral, clique em
   *Sair* e confirme que volta para `login.html`.

5. **Publique.** Envie `login.html`, `painel.html`, a pasta `js/` e este
   `README.md` para o mesmo repositório GitHub que já hospeda o site
   (`git add`, `git commit`, `git push`). O GitHub Pages atualiza sozinho em
   menos de um minuto.

6. **Acesse pelo domínio.** Depois de publicado, entre em
   `https://tatiribeirougc.com.br/login.html` para usar o painel de
   qualquer lugar.

## Onde ficam os números

O painel lê as tabelas `portfolio_events` (visitas, cliques, vídeos vistos) e
`portfolio_leads` (mensagens de contato). Elas começam vazias: os números só
aparecem depois que o site do portfólio passar a gravar eventos nelas (isso é
um passo separado, feito pelo servidor do site, não pelo painel).
