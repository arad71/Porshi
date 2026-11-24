# porshi.tech

The Porshi Tech website. Porshi means neighbour in Bangla.

The whole site is one file: `site/index.html`.

## Deploying

Every push to `main` that changes `site/` deploys to the Contabo server automatically
(see `.github/workflows/deploy.yml`). You can also run it by hand from the **Actions** tab.

The first run creates the Nginx site for `porshi.tech` and `www.porshi.tech` and, once DNS
points at the server, a free Let's Encrypt HTTPS certificate. Later runs only upload the files.
Other sites on the server (pms, cams and so on) are never touched.

### Repository secrets

Settings → Secrets and variables → Actions:

| Name | Value |
|---|---|
| `CONTABO_HOST` | the server's IP address |
| `CONTABO_SSH_KEY` | the private SSH key GitHub uses to log in |
| `CERT_EMAIL` | email for Let's Encrypt certificate notices |
| `CONTABO_USER` | optional, defaults to `root` |

### DNS

A records for `@` and `www` pointing at the server's IP.

## Editing

Edit `site/index.html`, commit, push. Products live in the `prods` list in the page script;
add an entry there to show a new product.
