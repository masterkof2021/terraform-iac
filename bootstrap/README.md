# Backend compartido en S3

El backend ya está creado y ambos estados están migrados. La infraestructura existente del laboratorio conserva sus 18 recursos administrados y todas sus salidas. El bucket y sus protecciones se administran en este módulo, separado de los EC2 y la red.

| Dato | Valor |
|---|---|
| Cuenta | `222234418877` |
| Región | `us-east-2` |
| Bucket | `globomatics-tofu-state-222234418877-us-east-2` |
| Estado del laboratorio | `globomatics/lab/terraform.tfstate` |
| Estado del backend | `globomatics/backend/terraform.tfstate` |
| Estado de Pulumi | `globomatics/pulumi/` |
| Bloqueo | Archivo `.tflock` junto a cada estado; `use_lockfile = true` |

El bucket tiene versionado, cifrado SSE-S3, ACL deshabilitadas, bloqueo de acceso público y una política que exige HTTPS. No se necesita DynamoDB. `prevent_destroy` y `force_destroy = false` protegen el bucket desde OpenTofu; no impiden la eliminación directa por un administrador en AWS.

## Colaboradores

Para trabajar en el laboratorio, usa los comandos del [README principal](../README.md). No ejecutes este módulo para crear un EC2 nuevo: los recursos del laboratorio se declaran en los archivos `.tf` de la carpeta superior.

Los permisos se concentran en el **grupo IAM `globomatics-shared-state`**. Este módulo crea el grupo, le inserta la política `globomatics-shared-state` (definida en `../iam/state-access.json`) y le adjunta `AmazonEC2FullAccess`, `AmazonVPCFullAccess` y `SignInLocalDevelopmentAccess` (esta última habilita `aws login`). Cada compañero se agrega al grupo con la variable `shared_state_users`, cuyo valor por defecto es `["opentofu", "usuario1", "usuario2"]`:

```hcl
# Para sumar a alguien, agrega su usuario IAM y aplica el módulo.
shared_state_users = ["opentofu", "usuario1", "usuario2", "usuario3"]
```

La política del estado permite leer y escribir el estado del laboratorio (y el de Pulumi) y crear/eliminar su bloqueo. No concede borrado del estado, administración del bucket ni acceso al prefijo del backend. No se comparten claves de acceso ni se publica el bucket. Todos deben usar el workspace `default` y actualizar el código desde GitHub antes de planificar. La cuenta del proyecto es `222234418877`; los usuarios entran con `aws login --profile proyecto --region us-east-2`.

### Políticas propias que ya existan

Si la cuenta ya tiene las políticas `OpenTofuReadAmazonLinuxAMI`, `OpenTofuResourceGroupsCreate` y `OpenTofuTagGlobomaticsResourceGroup` (necesarias para planificar), pásalas al grupo sin recrearlas:

```hcl
shared_state_extra_policy_arns = [
  "arn:aws:iam::222234418877:policy/OpenTofuReadAmazonLinuxAMI",
  "arn:aws:iam::222234418877:policy/OpenTofuResourceGroupsCreate",
  "arn:aws:iam::222234418877:policy/OpenTofuTagGlobomaticsResourceGroup",
]
```

### Si el grupo ya existe en AWS

Este módulo declara el grupo `globomatics-shared-state`. Si un administrador ya lo creó a mano, impórtalo **antes** de `apply` para no duplicarlo:

```bash
tofu -chdir=bootstrap import aws_iam_group.shared_state globomatics-shared-state
```

La política insertada, las asignaciones de políticas administradas y la pertenencia de usuarios se aplican de forma idempotente sobre el grupo importado.

## Administrar el backend existente

Usa una identidad autorizada para administrar el bucket y su política IAM. El usuario `opentofu` del laboratorio no tiene esos permisos. El archivo `../iam/backend-admin.json` es una política S3 limitada al bucket; no incluye los permisos IAM necesarios para gestionar la política del usuario.

Desde la carpeta `terraform/`, con un perfil administrativo autenticado mediante `aws login`:

```bash
python3 scripts/tofu-session.py --aws-profile default -chdir=bootstrap init
python3 scripts/tofu-session.py --aws-profile default -chdir=bootstrap plan -out=backend.tfplan
python3 scripts/tofu-session.py --aws-profile default -chdir=bootstrap apply backend.tfplan
```

El adaptador existe porque el backend de OpenTofu 1.11.5 no reconoce directamente las sesiones `login_session` de la CLI. Exporta las credenciales temporales solo al entorno del proceso hijo, sin imprimirlas ni escribirlas en el repositorio. Cada invocación vuelve a obtener credenciales de la sesión vigente.

## Migración ya realizada

La creación se hizo inicialmente con estado local. Después de verificar el bucket, se activó `backend.tf` y se ejecutó `init -migrate-state` para ambos módulos. La comparación posterior confirmó que recursos, atributos y salidas coinciden íntegramente con los respaldos de origen. El backend S3 inicializó su propio `lineage` y contador `serial`; los metadatos del antiguo backend local no se deben usar como referencia para escribir sobre el nuevo estado.

Las copias previas se conservan en `../state-backups/`, con acceso local restringido y excluidas de Git. Conserva también una copia segura fuera del equipo. Las copias locales de trabajo se retiraron después de verificar S3.

En otros equipos solo se ejecuta `tofu init`: no se debe volver a migrar un estado local ni subir un archivo `.tfstate` manualmente. No uses `-reconfigure` para trasladar estados, porque ese modo no los copia.

## Verificar y recuperar

```bash
AWS_PROFILE=opentofu tofu state list
python3 scripts/tofu-session.py --aws-profile default -chdir=bootstrap state list
aws s3api get-bucket-versioning --bucket globomatics-tofu-state-222234418877-us-east-2 --profile default
aws s3api get-public-access-block --bucket globomatics-tofu-state-222234418877-us-east-2 --profile default
aws s3api get-bucket-encryption --bucket globomatics-tofu-state-222234418877-us-east-2 --profile default
```

El versionado conserva estados anteriores; no hay expiración automática de versiones. Para recuperar una versión, coordina una pausa del equipo y revisa la versión seleccionada antes de restaurarla. No fuerces escrituras ni desbloqueos mientras otro compañero esté trabajando. Revisa el crecimiento de versiones y bloqueos según el uso.

Para auditoría se recomienda habilitar eventos de datos de CloudTrail, registros de acceso S3 en un destino separado y cifrado, y métricas/alarmas de CloudWatch. No se aprovisionan esos servicios aquí; su habilitación requiere evaluar los cargos adicionales.

## Pruebas

```bash
tofu -chdir=bootstrap fmt -check
tofu -chdir=bootstrap validate
tofu -chdir=bootstrap test
```

Las pruebas usan proveedores simulados. Destruir el laboratorio desde el módulo principal no elimina el bucket ni este módulo de administración.

Fuentes: [backend S3 de OpenTofu](https://opentofu.org/docs/v1.11/language/settings/backends/s3/), [seguridad de S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html). El almacenamiento de todas las versiones y las solicitudes generan cargos según las [tarifas de Amazon S3](https://aws.amazon.com/s3/pricing/).
