# api-curso-db

Docker do banco (PostgreSQL), da API de tarefas e do Nginx. Tudo roda na mesma EC2,
só com Docker (sem PM2 e sem nada instalado direto no servidor além do Docker).

```
Internet ──80──▶ nginx ──▶ api:3000 ──▶ db:5432
                 (público)  (só interno)  (só interno)
```

* **nginx**: proxy reverso, única porta aberta para a internet (80).
* **api**: só acessível pelo Nginx ou de dentro do servidor (`curl localhost:3000`).
* **db**: só acessível pela API ou de dentro do servidor (`psql` na porta `DB_PORT_HOST`).

```
curso/
├── api-curso/       # código da API (tem o Dockerfile da API)
└── api-curso-db/    # este repositório: banco + docker-compose
```

As duas pastas precisam ficar lado a lado, porque o compose monta a API a partir de `../api-curso`.

## Rodar local

```bash
cp .env.example .env      # trocar senha e TOKEN_KEY
docker compose up -d --build
curl http://localhost/health        # pelo Nginx
curl http://localhost:3000/health   # direto na API
```

## Deploy na EC2 (Ubuntu)

1. **Security Group da instância:**
   * SSH (22): somente "My IP"
   * HTTP (80): 0.0.0.0/0
   * **Não** liberar a 3000 nem a 5432: API e banco só são acessados de dentro da EC2 (o público entra pelo Nginx na 80).

2. **Instalar Docker e Git:**
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y git
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker ubuntu
   exit   # sair e entrar de novo no SSH para o grupo docker valer
   ```

3. **Baixar os projetos (lado a lado):**
   ```bash
   mkdir ~/curso && cd ~/curso
   git clone https://github.com/SEU_USUARIO/api-curso.git
   git clone https://github.com/SEU_USUARIO/api-curso-db.git
   cd api-curso-db
   cp .env.example .env
   nano .env   # trocar POSTGRES_PASSWORD e TOKEN_KEY
   ```

4. **Subir tudo:**
   ```bash
   docker compose up -d --build
   ```
   Os containers usam `restart: unless-stopped`: voltam sozinhos se caírem ou se a EC2 reiniciar.

5. **Testar:** `http://IP_PUBLICO/health` e as rotas do `requests.http` da API.

6. **Atualizar depois de um push:**
   ```bash
   ./deploy.sh
   ```

## Comandos úteis

```bash
docker compose ps                 # status
docker compose logs -f api        # logs da API
docker compose logs -f nginx      # logs do Nginx (acessos e erros 502)
docker compose logs -f db         # logs do banco
docker compose exec db psql -U postgres -d api_tarefas   # SQL no banco
docker compose restart api        # reiniciar só a API
docker compose up -d --build nginx   # aplicar mudança no nginx/default.conf
```

## Atenção

* O `schema.sql` só roda na **primeira** subida (volume vazio). Alterações depois
  disso: rodar o SQL pelo `psql` acima.
* Se o Nginx responder **502 Bad Gateway**, a API caiu ou ainda está subindo: `docker compose logs api`.
* `docker compose down -v` **apaga o volume e todos os dados do banco**. Use só `docker compose down`.
* O IP público muda se a instância for parada e iniciada de novo (Elastic IP resolve, mas pode gerar custo).
* Backup manual: `docker compose exec db pg_dump -U postgres api_tarefas > backup.sql`
