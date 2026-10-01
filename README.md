# api-curso-db

Docker do banco (PostgreSQL) e da API de tarefas. Os dois rodam na mesma EC2,
só com Docker (sem PM2 e sem Nginx).

```
curso/
├── api-curso/       # código da API (tem o Dockerfile da API)
└── api-curso-db/    # este repositório: banco + docker-compose
```

As duas pastas precisam ficar lado a lado, porque o compose monta a API a partir de `../api-curso`.

## Rodar local

```bash
cp .env.example .env      # trocar senha e TOKEN_KEY; local use API_PORT_HOST=3000
docker compose up -d --build
curl http://localhost:3000/health
```

## Deploy na EC2 (Ubuntu)

1. **Security Group da instância:**
   * SSH (22): somente "My IP"
   * HTTP (80): 0.0.0.0/0
   * **Não** liberar a 5432: o banco só é acessado de dentro da EC2.

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
docker compose logs -f db         # logs do banco
docker compose exec db psql -U postgres -d api_tarefas   # SQL no banco
docker compose restart api        # reiniciar só a API
```

## Atenção

* O `schema.sql` só roda na **primeira** subida (volume vazio). Alterações depois
  disso: rodar o SQL pelo `psql` acima.
* `docker compose down -v` **apaga o volume e todos os dados do banco**. Use só `docker compose down`.
* O IP público muda se a instância for parada e iniciada de novo (Elastic IP resolve, mas pode gerar custo).
* Backup manual: `docker compose exec db pg_dump -U postgres api_tarefas > backup.sql`
