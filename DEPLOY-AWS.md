# Deploy na AWS: EC2 + Docker + CloudFront

Passo a passo para colocar o sistema de tarefas no ar em uma instância EC2, tudo em Docker
(Nginx + front Next.js + API + PostgreSQL), com o Amazon CloudFront na frente.

```
                    HTTPS                         HTTP :80
Cliente ──────────▶ CloudFront ─────────────────▶ EC2 ─▶ nginx ─┬─ /api/* ─▶ api:3000 ─▶ db:5432
            (dxxxx.cloudfront.net)                              └─ /*     ─▶ front:3000
                                                               (containers Docker)
```

Front e API ficam no **mesmo endereço**: o site em `/` e a API em `/api/...`
(o Nginx tira o `/api` antes de repassar, então `/api/tasks` chega na API como `/tasks`).

**Por que o CloudFront na frente?**

* **HTTPS de graça:** o CloudFront já entrega `https://dxxxx.cloudfront.net` com certificado válido,
  sem precisar configurar Certbot no servidor.
* **EC2 protegida:** no fim, a porta 80 da EC2 só aceita conexões vindas do CloudFront.
* **Domínio próprio** (opcional): fica fácil apontar `api.seudominio.com` para o CloudFront.

> Requisitos: conta AWS com acesso a EC2 e CloudFront, os repositórios `api-curso`,
> `api-curso-db` e `api-curso-front` no GitHub, e um cliente HTTP (Postman ou REST Client).

---

## Parte 1: Criar a EC2

### 1.1 Lançar a instância

No console: **EC2 → Instances → Launch instances**

| Campo | Valor |
|---|---|
| Name | `api-curso` |
| AMI | **Ubuntu Server 24.04 LTS** (64-bit x86) |
| Instance type | `t3.micro` (nível gratuito/créditos) ou `t3.small` se tiver orçamento |
| Key pair | **Create new key pair** → `api-curso` → RSA → `.pem` → guarde o arquivo |
| Storage | 20 GiB gp3 (as imagens Docker e o banco ocupam espaço) |

Em **Network settings → Edit**, crie um Security Group novo chamado `api-curso-sg`:

| Tipo | Porta | Origem | Para quê |
|---|---|---|---|
| SSH | 22 | **My IP** | Acessar o servidor |
| HTTP | 80 | `0.0.0.0/0` | Temporário: testar antes do CloudFront (fechamos na Parte 5) |

**Não** abra as portas 3000 (API) e 5432 (banco). Elas ficam acessíveis só de dentro da EC2.

Clique em **Launch instance**.

### 1.2 Fixar o IP com um Elastic IP

O CloudFront aponta para o endereço da EC2. Sem um Elastic IP, o IP público (e o DNS público)
**muda** toda vez que a instância é parada e iniciada, e o CloudFront para de funcionar.

1. **EC2 → Elastic IPs → Allocate Elastic IP address → Allocate**
2. Selecione o IP criado → **Actions → Associate Elastic IP address**
3. Instance: `api-curso` → **Associate**

Anote:
* **Public IPv4 address** (o Elastic IP), por exemplo `54.123.45.67`
* **Public IPv4 DNS**, por exemplo `ec2-54-123-45-67.compute-1.amazonaws.com`
  (fica em EC2 → Instances → selecionar a instância → Details). O CloudFront vai usar este DNS.

> Custo: a AWS cobra por todo IPv4 público por hora, associado ou não. Se desassociar o Elastic IP,
> libere-o (Release) para não pagar à toa.

---

## Parte 2: Preparar o servidor

### 2.1 Acessar por SSH

Pelo navegador: **EC2 → Instances → selecionar → Connect → EC2 Instance Connect → Connect**.

Ou pelo terminal (WSL):

```bash
chmod 400 ~/api-curso.pem
ssh -i ~/api-curso.pem ubuntu@54.123.45.67
```

### 2.2 Atualizar o sistema e criar swap

A `t3.micro` tem só 1 GB de RAM. O swap evita que o build das imagens trave por falta de memória.

```bash
sudo apt update && sudo apt upgrade -y

sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h   # deve mostrar Swap: 2.0Gi
```

### 2.3 Instalar Docker e Git

```bash
sudo apt install -y git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
exit
```

Entre de novo no SSH (para o grupo `docker` valer) e confira:

```bash
docker --version
docker compose version
docker ps        # lista vazia, sem erro de permissão
```

> Use **só** esta instalação do Docker. Não instale também pelo `snap`: dois Docker ao mesmo tempo
> brigam pela rede e as portas param de responder.

---

## Parte 3: Subir a aplicação

### 3.1 Baixar os projetos

As três pastas precisam ficar **lado a lado**, porque o compose monta a API e o front a partir de `../api-curso` e `../api-curso-front`.

```bash
mkdir ~/curso && cd ~/curso
git clone https://github.com/SEU_USUARIO/api-curso.git
git clone https://github.com/SEU_USUARIO/api-curso-db.git
git clone https://github.com/SEU_USUARIO/api-curso-front.git
```

> Repositório privado? O `git clone` vai pedir usuário e senha: use seu usuário do GitHub e um
> **Personal Access Token** (GitHub → Settings → Developer settings → Tokens) no lugar da senha.

### 3.2 Configurar o `.env`

```bash
cd ~/curso/api-curso-db
cp .env.example .env

# Gere valores fortes:
openssl rand -hex 16   # use como POSTGRES_PASSWORD
openssl rand -hex 32   # use como TOKEN_KEY

nano .env
```

O `.env` final fica assim:

```
POSTGRES_DB=api_tarefas
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=<valor gerado>
TOKEN_KEY=<valor gerado>
HTTP_PORT=80
API_PORT_HOST=3000
FRONT_PORT_HOST=3001
DB_PORT_HOST=5432
```

> O `TOKEN_KEY` assina os tokens de login. Se ele mudar, todos os usuários precisam logar de novo.
> Nunca suba o `.env` para o GitHub.

### 3.3 Subir os containers

```bash
docker compose up -d --build
docker compose ps
```

O primeiro build demora alguns minutos (o build do Next é o mais pesado).
Os quatro devem aparecer como `Up`, e `api-curso`, `api-curso-db` e `api-curso-front` com `(healthy)`:

```
api-curso         Up (healthy)   127.0.0.1:3000->3000/tcp
api-curso-db      Up (healthy)   127.0.0.1:5432->5432/tcp
api-curso-front   Up (healthy)   127.0.0.1:3001->3000/tcp
api-curso-nginx   Up             0.0.0.0:80->80/tcp
```

### 3.4 Testar

Dentro do servidor:

```bash
curl localhost/api/health      # API pelo Nginx
curl localhost:3000/health     # direto na API (sem o /api)
curl -I localhost/login        # front pelo Nginx (HTTP/1.1 200)
```

Do seu computador:

* Navegador: `http://54.123.45.67/` abre a tela de login. Crie uma conta e adicione uma tarefa.
* Postman: `http://54.123.45.67/api/health` → `{"status":"ok","database":"ok"}`

> Pelo Nginx, **todas as rotas da API levam o prefixo `/api`**: `/api/users/login`, `/api/tasks`, etc.

Os containers usam `restart: unless-stopped`: voltam sozinhos se caírem ou se a EC2 reiniciar.
Para confirmar: `sudo reboot`, espere um minuto e teste de novo.

---

## Parte 4: Criar o CloudFront

### 4.1 Criar uma cache policy para a API

A API não pode ter as respostas guardadas em cache (cada usuário vê as próprias tarefas), e o
CloudFront precisa repassar o header `Authorization` com o token. A política abaixo faz as duas coisas.
Ela vale também para as páginas do front; os arquivos estáticos do Next ganham cache no passo 4.3.

**CloudFront → Policies → Cache → Create cache policy**

| Campo | Valor |
|---|---|
| Name | `api-sem-cache` |
| Minimum TTL | `0` |
| Default TTL | `0` |
| Maximum TTL | `1` |
| Headers | **Include the following headers** → `Authorization` |
| Query strings | **All** (o filtro `?done=true` precisa chegar na API) |
| Cookies | None |
| Compression (Gzip/Brotli) | marcados |

Com Default TTL `0`, nada fica em cache (a API não manda `Cache-Control`). Colocar o `Authorization`
na política é o que garante que o CloudFront repasse o token para a API.

### 4.2 Criar a distribuição

**CloudFront → Distributions → Create distribution**

**Origin**

| Campo | Valor |
|---|---|
| Origin domain | o **Public IPv4 DNS** da EC2: `ec2-54-123-45-67.compute-1.amazonaws.com` (o CloudFront não aceita IP, só nome) |
| Protocol | **HTTP only** |
| HTTP port | `80` |
| Name | `api-curso-ec2` |

**Default cache behavior**

| Campo | Valor |
|---|---|
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE** (sem isso, POST e DELETE dão 403) |
| Cache policy | `api-sem-cache` (criada no 4.1) |
| Origin request policy | **AllViewerExceptHostHeader** |
| Response headers policy | nenhuma (o CORS já é tratado pela API) |

**Settings**

| Campo | Valor |
|---|---|
| Price class | **Use all edge locations** (inclui a América do Sul; as outras classes deixam o Brasil de fora) |
| Web Application Firewall (WAF) | Do not enable (opcional, tem custo) |
| Alternate domain name | vazio por enquanto (ver Parte 6) |

Clique em **Create distribution**. O status fica **Deploying** por alguns minutos.
Anote o **Distribution domain name**: `dxxxxxxxxxxxx.cloudfront.net`.

### 4.3 Cache para os arquivos estáticos do front

Os arquivos em `/_next/static/` (JavaScript, CSS, fontes) têm um código no nome que muda a cada build,
então podem ficar em cache sem risco de mostrar versão velha. Isso deixa o site mais rápido.

**Sua distribuição → Behaviors → Create behavior**

| Campo | Valor |
|---|---|
| Path pattern | `/_next/static/*` |
| Origin | `api-curso-ec2` |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | GET, HEAD |
| Cache policy | **CachingOptimized** |
| Origin request policy | nenhuma |

### 4.4 Testar pelo CloudFront

**No navegador:** abra `https://dxxxxxxxxxxxx.cloudfront.net/`, crie uma conta, adicione uma tarefa,
conclua (deve aparecer "feita em ...") e recarregue a página: a tarefa continua lá.

**No Postman** (troque o `@base` do `requests.http` para `https://dxxxxxxxxxxxx.cloudfront.net/api`), nesta ordem:

1. `GET /health` → `{"status":"ok","database":"ok"}`
2. `POST /users/persist` com `{ "name": "Ana", "email": "ana@teste.com", "password": "123456" }` → `type: success` e um `token`
3. `GET /users/me` com `Authorization: Bearer <token>` → os dados da Ana
   * Se voltar **"Token não informado"**, o CloudFront não está repassando o `Authorization`.
     Confira a cache policy do passo 4.1.
4. `POST /tasks/persist` com `{ "title": "Testar o CloudFront" }` → tarefa criada
5. `POST /tasks/persist/1` com `{ "done": true }` → `done_at` preenchido
6. `GET /tasks?done=true` → só a tarefa concluída
   * Se vier a lista inteira, a query string não chegou. Confira **Query strings: All** na cache policy.
7. `DELETE /tasks/1` → `deletado com sucesso`
   * Se voltar **403 do CloudFront**, faltou liberar os métodos no passo 4.2.

---

## Parte 5: Fechar a EC2 para acesso direto

Agora o público deve entrar só pelo CloudFront. A AWS mantém uma lista oficial com os IPs do
CloudFront (managed prefix list), e dá para usá-la direto no Security Group.

1. **VPC → Managed prefix lists** → procure `com.amazonaws.global.cloudfront.origin-facing`
   e anote o ID (`pl-xxxxxxxx`)
2. **EC2 → Security Groups → `api-curso-sg` → Edit inbound rules**
3. Na regra **HTTP 80**, troque a origem `0.0.0.0/0` pelo prefix list `pl-xxxxxxxx`
4. **Save rules**

Regras finais:

| Tipo | Porta | Origem |
|---|---|---|
| SSH | 22 | My IP |
| HTTP | 80 | `com.amazonaws.global.cloudfront.origin-facing` |

Teste:
* `https://dxxxxxxxxxxxx.cloudfront.net/` e `.../api/health` → continuam funcionando
* `http://54.123.45.67/` → **não responde mais** (timeout). É o esperado.

> Se der erro ao salvar ("rules limit exceeded"): o prefix list conta como cerca de 55 regras.
> Deixe só as duas regras acima nesse Security Group.

---

## Parte 6 (opcional): Domínio próprio, ex. `api.seudominio.com`

1. **Certificado:** **ACM → região `us-east-1` (N. Virginia)** → Request certificate → Public →
   `api.seudominio.com` → DNS validation. Crie o registro CNAME que ele pedir no seu DNS e espere ficar **Issued**.
   * O CloudFront só usa certificados da região `us-east-1`.
2. **CloudFront → sua distribuição → Edit (General)**:
   * Alternate domain name: `api.seudominio.com`
   * Custom SSL certificate: o certificado do passo 1
3. **DNS:**
   * Route 53: registro **A → Alias → CloudFront distribution**
   * Outro provedor (Registro.br, Cloudflare etc.): registro **CNAME** `api` → `dxxxxxxxxxxxx.cloudfront.net`
4. Teste `https://api.seudominio.com/` e `https://api.seudominio.com/api/health`

---

## Atualizar a aplicação

No seu computador: altere o código, faça commit e `git push` nos repositórios (api, front ou db). No servidor:

```bash
cd ~/curso/api-curso-db
./deploy.sh
```

O script faz `git pull` nos três projetos, recria os containers e limpa imagens antigas.
Os dados do banco ficam no volume `db-data` e **não** são apagados.

Não é preciso mexer no CloudFront: as páginas e a API não têm cache, e os arquivos de `/_next/static/` mudam de nome a cada build.

---

## Comandos úteis no servidor

```bash
cd ~/curso/api-curso-db
docker compose ps                     # status dos containers
docker compose logs -f api            # logs da API
docker compose logs -f front          # logs do front (Next)
docker compose logs -f nginx          # acessos e erros do Nginx
docker compose exec db psql -U postgres -d api_tarefas      # SQL no banco
docker compose exec db pg_dump -U postgres api_tarefas > backup-$(date +%F).sql   # backup
docker compose restart api            # reiniciar só a API
```

> **Nunca** rode `docker compose down -v`: o `-v` apaga o volume e **todos os dados do banco**.

---

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| CloudFront responde **502 Bad Gateway** | O CloudFront não alcança a EC2 | Container `nginx` está `Up`? Security Group libera a 80 para o CloudFront? Origin com **HTTP only** na porta 80? |
| CloudFront responde **504 Gateway Timeout** | Security Group bloqueando ou EC2 parada | Confira o prefix list na regra da porta 80 e se a instância está `running` |
| Nginx responde **502** (página com `nginx`) | A API ou o front caiu ou ainda está subindo | `docker compose ps`, `docker compose logs api` e `docker compose logs front` |
| Site abre mas login dá "Sem conexão com o servidor" ou erro 404 | `/api` não chega na API | Confira o `nginx/default.conf` (`location /api/` com `proxy_pass http://api/;`, com a barra no fim) |
| **403** do CloudFront em POST/DELETE | Métodos não liberados | Behavior → Allowed HTTP methods → GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE |
| **"Token não informado"** só pelo CloudFront | `Authorization` não repassado | Cache policy com o header `Authorization` (passo 4.1) |
| `?done=true` ignorado | Query string não repassada | Cache policy com **Query strings: All** |
| Postman dá 404 do Next (página HTML) | Faltou o prefixo `/api` | Use `/api/tasks`, `/api/users/login`… |
| `"database":"indisponível"` | Banco fora ou `.env` errado | `docker compose ps` e `docker compose logs db` |
| Parou de funcionar depois de parar/iniciar a EC2 | IP mudou | Use Elastic IP (passo 1.2) e confira o Origin domain no CloudFront |
| Build trava ou o container morre (`Killed`) | Falta de memória | Confira o swap (passo 2.2) |

---

## Limpeza (para não gerar custo)

Quando não precisar mais:

1. **CloudFront:** Disable na distribuição, espere terminar e depois Delete
2. **EC2:** Instance state → **Terminate** (não só Stop)
3. **Elastic IP:** Release
4. **Security Group** `api-curso-sg` e **Key pair** `api-curso`: Delete
5. **Cache policy** `api-sem-cache`: Delete
6. Alguns dias depois: confira **Billing → Bills** e o **Cost Explorer**
