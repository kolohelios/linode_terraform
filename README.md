# Linode Terraform

This is my personal cluster's configuration.

## Development

### Linting

run `terraform fmt`

* terraform.tfstate should not be commited to source control

```bash
LINODE_TOKEN={{Linode PAT}} terraform apply
```

`terraform-secrets.tfvars`:
```
linode_token = ""
letsencrypt_cloudflare_api_token = ""
letsencrypt_email = ""
```

`terraform plan -var-file=terraform-secrets.tfvars -var-file=terraform.tfvars`

## Adding a new domain

* purchase domain
* establish zone at Cloudflare

## Notes
* Cloudflare token MUST have Edit Zone permissions
* Cloudflare SSL settings must be Full (strict)
