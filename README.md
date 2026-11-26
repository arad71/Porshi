# porshi.tech

The Porshi Tech website. Porshi means neighbour in Bangla.

The whole site is one file: `site/index.html`.

## Deploying

Every push to `main` that changes `site/` deploys to the Contabo server automatically
(see `.github/workflows/deploy.yml`). You can also run it by hand from the **Actions** tab.

The site is served by a small Nginx container (`porshi-site`, on `127.0.0.1:8090`) and published
through the server's existing **Caddy**, which also handles HTTPS. The first run appends a
`porshi.tech` block to the Caddyfile (after backing it up and validating it; if Caddy rejects it,
the file is restored unchanged). Later runs only upload the files. Other sites in the Caddyfile
(pms, cams, motors and so on) are never changed. Works with Caddy installed on the system or in Docker.

### Repository secrets

Settings → Secrets and variables → Actions:

| Name | Value |
|---|---|
| `CONTABO_HOST` | the server's IP address |
| `CONTABO_SSH_KEY` | the private SSH key GitHub uses to log in |
| `SITE_PORT` | optional, defaults to `8090`; change only if that port is taken |
| `CONTABO_USER` | optional, defaults to `root` |

### DNS

A records for `@` and `www` pointing at the server's IP.

## Editing

Edit `site/index.html`, commit, push. Products live in the `prods` list in the page script;
add an entry there to show a new product.
