# Globomatics en AWS

Esta carpeta contiene la IaC y se administra de forma independiente de la aplicación, ubicada en `../asistencia/`. La configuración, pruebas, archivo de bloqueo y estado local se trasladaron desde `asistencia/infra/aws/` sin cambiar los recursos ni el estado. El traslado no requiere aplicar cambios en AWS.

La configuración de Nginx y systemd pertenece al despliegue de la aplicación y permanece en `../asistencia/deploy/`. Para instalar y actualizar los servicios, consulta la [guía de despliegue manual](../asistencia/docs/despliegue-manual-aws.md).

La configuración aprovisiona únicamente infraestructura básica en **us-east-2**: grupo de recursos, redes, reglas de seguridad, clave pública y dos EC2 con sus discos. Toda instalación de herramientas y servicios, configuración de los servidores y despliegue de la aplicación se realizará manualmente por SSH. La configuración no utiliza `user_data`, provisionadores ni plantillas de configuración de aplicaciones.

| Recurso | Configuración |
|---|---|
| Grupo de recursos | `rg-globomatics-lab`, filtro por etiqueta `Project=globomatics` |
| VPC y subred pública | `vpc-globomatics-lab` (`10.42.0.0/16`) y `subnet-publica-globomatics-lab` (`10.42.1.0/24`) |
| Salida a Internet | `igw-globomatics-lab` y tabla `rtb-publica-globomatics-lab` |
| Grupos de seguridad | `secgrp-cliente-globomatics-lab` y `secgrp-backend-globomatics-lab` |
| EC2 cliente | `ec2-cliente-globomatics-lab`, IP privada `10.42.1.10`, disco gp3 cifrado de 12 GiB |
| EC2 backend | `ec2-backend-globomatics-lab`, IP privada `10.42.1.20`, disco gp3 cifrado de 20 GiB |
| Ambos EC2 | `t3.micro`, Amazon Linux 2023 x86_64, kernel 6.18, IP pública e IMDSv2 obligatorio |
| SSH | TCP 22 en ambos, únicamente desde `181.114.108.136/32` |
| Web | TCP 80 y 443 al cliente desde Internet |
| API | TCP 8090 al backend, únicamente desde el grupo de seguridad del cliente |
| Base de datos | Sin reglas de entrada para puertos de base de datos |

Los nombres o etiquetas `Name` empiezan por el tipo de recurso y terminan con el proyecto y entorno `globomatics-lab`: `rg-`, `vpc-`, `subnet-`, `igw-`, `rtb-`, `ec2-`, `ebs-`, `secgrp-`, `sgr-ingress-`, `sgr-egress-` y `key-`. La asociación de la tabla de rutas no admite nombres ni etiquetas. AWS crea además elementos implícitos de la VPC, como el grupo de seguridad predeterminado; los servidores utilizan exclusivamente los grupos propios declarados aquí. El Resource Group reúne los tipos compatibles con AWS Resource Groups que tengan la etiqueta del proyecto.

## Organización de archivos

Todos los archivos `.tf` de esta carpeta forman un único módulo y se cargan juntos. Esta separación conserva los nombres, atributos y dependencias de los recursos; no requiere migrar el estado ni ejecutar `apply`.

| Archivo | Responsabilidad |
|---|---|
| `config.tf` | Backend S3, versiones, proveedor AWS, variables, valores compartidos y grupo de recursos |
| `network.tf` | VPC, subred, gateway, rutas, grupos de seguridad y sus reglas |
| `compute.tf` | Consultas de AMI/zonas, clave SSH e instancias EC2 con sus discos |
| `outputs.tf` | Direcciones de servidores y comandos SSH |

El resto de carpetas organiza responsabilidades separadas:

| Carpeta | Responsabilidad |
|---|---|
| `bootstrap/` | Bucket S3 del estado, sus protecciones y el grupo IAM `globomatics-shared-state` |
| `iam/` | Políticas JSON: `state-access.json` (estado compartido) y `backend-admin.json` (administrar el bucket) |
| `pulumi/` | Proyecto Pulumi (TypeScript) que crea una VM EC2 y su Security Group |
| `tests/` | Pruebas de OpenTofu con proveedor simulado (no acceden a AWS) |
| `scripts/` | Adaptadores `tofu-session.py` y `pulumi-session.py` para credenciales de `aws login` |

## Clave SSH

Se creó un par Ed25519 local compartido por ambos EC2:

- Privada: `~/globomatics-ec2`, permisos `600`, sin frase de paso.
- Pública: `~/globomatics-ec2.pub`, permisos `644`.

OpenTofu importa **solo la pública** a AWS como `key-globomatics-lab`. No genera ni almacena la privada en el estado. Guarda una copia segura de la privada; no la subas a Git ni a los servidores. Al usar otra máquina, proporciona `-var='ssh_public_key_path=/ruta/globomatics-ec2.pub'` y usa la privada correspondiente para SSH.

En otra máquina puedes recuperar la **clave pública** existente desde AWS (no requiere la privada). En Windows PowerShell:

```powershell
aws ec2 describe-key-pairs `
  --profile proyecto `
  --region us-east-2 `
  --key-names key-globomatics-lab `
  --include-public-key `
  --query "KeyPairs[0].PublicKey" `
  --output text | Out-File -FilePath "$HOME\globomatics-ec2.pub" -Encoding ascii
```

Equivalente en Bash:

```bash
aws ec2 describe-key-pairs \
  --profile proyecto \
  --region us-east-2 \
  --key-names key-globomatics-lab \
  --include-public-key \
  --query 'KeyPairs[0].PublicKey' \
  --output text > "$HOME/globomatics-ec2.pub"
```

Comprueba que el archivo contenga una clave OpenSSH y no el texto `None`. No generes una clave nueva: reemplazarla propondría cambios sobre el par del proyecto.

## Estado compartido en S3

El backend está configurado para el bucket `globomatics-tofu-state-222234418877-us-east-2`, en `us-east-2`, y la clave `globomatics/lab/terraform.tfstate`, con cifrado y bloqueo nativo S3. La creación y migración están completadas: S3 es el estado oficial compartido. Se verificó que la migración conserva los 18 recursos administrados del laboratorio y todas sus salidas. Los respaldos previos se conservan de forma privada en `state-backups/`, fuera de Git. Consulta la [guía del backend](bootstrap/README.md) para su administración.

`bootstrap/` administra el bucket y el acceso por separado; `iam/state-access.json` contiene los permisos del estado (OpenTofu y Pulumi) y `iam/backend-admin.json` los permisos S3 para administrar el bucket. El acceso se concentra en el **grupo IAM `globomatics-shared-state`**: se le inserta la política del estado y se le adjuntan las políticas administradas `AmazonEC2FullAccess`, `AmazonVPCFullAccess` y `SignInLocalDevelopmentAccess` (necesaria para `aws login`), y cada compañero se agrega al grupo con la variable `shared_state_users` (`opentofu`, `usuario1` y `usuario2` por defecto). Así, para sumar a alguien basta con agregar su usuario a la lista y aplicar el módulo; no se comparten claves ni se crean credenciales. La cuenta del proyecto es `222234418877` y la consola de los usuarios es `https://222234418877.signin.aws.amazon.com/console`.

Después de la migración, cada compañero inicia sesión con su propio usuario, obtiene el código y usa su identidad autorizada:

```bash
# Inicia sesion con tu usuario de la cuenta del proyecto (abre el navegador):
aws login --profile proyecto --region us-east-2
export AWS_PROFILE=proyecto
tofu init
tofu state list
tofu plan -lock-timeout=5m -out=globomatics.tfplan
```

Si tu perfil usa credenciales de `aws login`, el backend de OpenTofu 1.11.5 puede no reconocer `login_session` directamente. Usa el adaptador incluido, que obtiene credenciales temporales de la CLI y las entrega a OpenTofu solo en memoria:

```bash
python3 scripts/tofu-session.py --aws-profile proyecto init
python3 scripts/tofu-session.py --aws-profile proyecto plan -lock-timeout=5m
```

La sesión debe seguir vigente; cada invocación obtiene credenciales nuevas. Los perfiles que OpenTofu reconoce directamente, como el perfil actual `opentofu`, pueden usar los comandos habituales.

El proveedor y el backend toman las credenciales del entorno/perfil AWS. No hay perfiles personales ni claves de acceso en el código. El plan requiere también acceso a la clave SSH pública configurada mediante `ssh_public_key_path`; nunca se comparte la privada a través de S3 o Git.

El flujo del equipo es: actualizar el código desde GitHub, añadir o modificar recursos en los archivos `.tf`, revisar `tofu plan` y aplicar el plan. OpenTofu lee y actualiza automáticamente el mismo estado de S3. Así, un nuevo EC2 declarado y creado por un compañero queda registrado en la infraestructura común. Los demás deben actualizar también el código desde GitHub antes de planificar; compartir únicamente el estado sin sincronizar el código puede proponer eliminar recursos que su copia todavía no declara.

Los compañeros deben usar el mismo workspace `default` y la misma configuración de backend; no deben copiar un estado local ni ejecutar `init -migrate-state`. El bloqueo evita que dos operaciones escriban el estado al mismo tiempo; no uses `-lock=false` ni fuerces desbloqueos sin comprobar quién está trabajando. El acceso al estado contiene información de la infraestructura y no sustituye los permisos para crear o modificar los recursos AWS.

## Planificar y crear

Requiere OpenTofu >= 1.11 y < 2, acceso al registro de proveedores y credenciales de AWS configuradas fuera del código, por ejemplo mediante un perfil de AWS CLI. La identidad debe poder consultar AMIs en SSM y zonas disponibles, y administrar EC2/redes, claves, etiquetas y Resource Groups.

Desde la raíz de la carpeta `terraform`:

```bash
# Selecciona tu perfil autorizado:
export AWS_PROFILE=opentofu
tofu init
tofu validate
tofu plan -out=globomatics.tfplan
tofu apply globomatics.tfplan
tofu output servers
tofu output ssh_commands
```

El plan consulta `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-x86_64` en `us-east-2`; así selecciona la AMI oficial de la familia solicitada, sin seguir cambios de kernel de `kernel-default`. La selección de kernel está documentada por [Amazon Linux](https://docs.aws.amazon.com/linux/al2023/ug/kernel-update.html). Una nueva AMI publicada en ese parámetro puede proponer reemplazar las instancias en futuros planes; revisa siempre el plan antes de aplicar. La verificación posterior a la migración ya detectó una AMI diferente y un plan de reemplazo de ambos EC2 (`2 to add, 0 to change, 2 to destroy`); ese plan no se aplicó. Revisa la actualización de AMI y respalda MySQL antes de aceptar esos reemplazos.

Las IP públicas son asignadas automáticamente, sin Elastic IP; pueden cambiar al detener/iniciar un EC2. En ese caso vuelve a ejecutar `tofu apply -refresh-only`, consulta las salidas para conocer las direcciones vigentes. Las IP privadas se mantienen fijas. Si cambia tu IP administrativa, usa `-var='ssh_source_cidr=NUEVA_IP/32'` al planificar y aplicar.

Git solo debe contener código, documentación y los archivos `.terraform.lock.hcl`. `.gitignore` excluye estados, respaldos, planes, caché del backend, dependencias de Pulumi (`node_modules/`, `bin/`) y copias privadas en `state-backups/`. Si algún estado ya fue versionado en otra copia del repositorio, añadirlo a `.gitignore` no lo retira del índice ni del historial: revisa esa copia antes de compartirla.

S3 es el estado compartido oficial. El versionado permite recuperar versiones anteriores; conserva el bucket incluso si destruyes el laboratorio. S3 cobra por almacenamiento, versiones y solicitudes; consulta sus [tarifas](https://aws.amazon.com/s3/pricing/). EC2, almacenamiento e IPv4 públicas también pueden generar cargos.

## VM con Pulumi

Además de OpenTofu, el repositorio incluye un proyecto **Pulumi** en TypeScript (`pulumi/`) que crea una VM EC2 y su Security Group. El estado de Pulumi se guarda en el **mismo bucket compartido**, bajo el prefijo `globomatics/pulumi/`, por lo que el grupo `globomatics-shared-state` también puede consultarlo.

```bash
aws login --profile proyecto --region us-east-2
python3 scripts/pulumi-session.py --aws-profile proyecto login "s3://globomatics-tofu-state-222234418877-us-east-2/globomatics/pulumi?region=us-east-2"
cd pulumi
npm install
python3 ../scripts/pulumi-session.py --aws-profile proyecto stack select dev
python3 ../scripts/pulumi-session.py --aws-profile proyecto preview
python3 ../scripts/pulumi-session.py --aws-profile proyecto up
```

El `preview` debe mostrar 2 recursos a crear (`pulumi-vm-sg` y `pulumi-vm`). La salida `sshCommand` indica cómo conectarse con la clave compartida. Detalles y configuración en [`pulumi/README.md`](pulumi/README.md). `pulumi destroy` elimina **solo** la VM de Pulumi; no afecta los recursos de OpenTofu ni el bucket de estado.

## Verificación y eliminación

```bash
tofu fmt -check
tofu validate
# Pruebas con proveedor simulado: no acceden a AWS ni crean infraestructura.
tofu test
```

Las salidas `servers` y `ssh_commands` muestran las direcciones e instrucciones de conexión. Los puertos 80/443 y 8090 quedan autorizados en la red según las reglas indicadas; los servicios correspondientes se instalarán y configurarán manualmente.

Para eliminar la infraestructura, revisa `tofu plan -destroy` y ejecuta `tofu destroy` si corresponde. **Se borran ambos discos raíz, incluidos los datos de MySQL**: realiza una copia de seguridad antes de destruir o reemplazar el backend. Las llaves locales no se borran.
