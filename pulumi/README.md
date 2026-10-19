# VM de laboratorio con Pulumi

Proyecto Pulumi en TypeScript que crea una VM EC2 (y su Security Group) en
`us-east-2`. El estado de Pulumi se guarda en el **mismo bucket S3 compartido**
del laboratorio, bajo el prefijo `globomatics/pulumi/`.

| Dato | Valor |
|---|---|
| Proyecto | `globomatics-vm` |
| Stack | `dev` |
| Región | `us-east-2` |
| Backend de estado | `s3://globomatics-tofu-state-222234418877-us-east-2/globomatics/pulumi` |
| Recursos | `aws:ec2:SecurityGroup` y `aws:ec2:Instance` |
| Salidas | `publicIp`, `privateIp`, `instanceId`, `sshCommand` |

## Requisitos

- Pulumi CLI (`pulumi version`).
- AWS CLI v2 con soporte de `aws login`.
- Node.js 20 o superior y `npm`.
- Pertenecer al grupo IAM `globomatics-shared-state` (ver
  [backend compartido](../bootstrap/README.md)). Ese grupo incluye
  `SignInLocalDevelopmentAccess`, necesaria para `aws login`.
- Que exista el key pair `key-globomatics-lab` en la cuenta (lo crea OpenTofu).
  Pulumi solo usa el **nombre** del key pair; no lee la clave pública.

## 1. Iniciar sesión en AWS

Cada compañero usa **su propio usuario** de la cuenta `222234418877`:

```powershell
aws login --profile proyecto --region us-east-2
```

Cuando se abra el navegador, ingresa con las credenciales de tu usuario
(`usuario1`, `usuario2`, etc.). La sesión queda en el perfil `proyecto`.

## 2. Iniciar sesión en el backend de Pulumi

El backend S3 necesita credenciales temporales. Si `pulumi` no reconoce
directamente la sesión de `aws login`, usa el adaptador incluido:

```powershell
python ..\scripts\pulumi-session.py --aws-profile proyecto login "s3://globomatics-tofu-state-222234418877-us-east-2/globomatics/pulumi?region=us-east-2"
```

El adaptador obtiene credenciales temporales con
`aws configure export-credentials` y las entrega a Pulumi **solo en memoria**.

## 3. Instalar dependencias y seleccionar el stack

```powershell
npm install
python ..\scripts\pulumi-session.py --aws-profile proyecto stack select dev
```

Si el stack todavía no existe:

```powershell
python ..\scripts\pulumi-session.py --aws-profile proyecto stack init dev
```

## 4. Revisar y crear la VM

```powershell
python ..\scripts\pulumi-session.py --aws-profile proyecto preview
python ..\scripts\pulumi-session.py --aws-profile proyecto up
python ..\scripts\pulumi-session.py --aws-profile proyecto stack output
```

`preview` debe mostrar **2 recursos a crear** (`pulumi-vm-sg` y `pulumi-vm`).
Revisa siempre el preview antes de aceptar el `up`.

## 5. Conectarse

La salida `sshCommand` indica el comando. Usa la clave privada compartida del
proyecto (`~/globomatics-ec2`, nunca versionada):

```powershell
ssh -i ~/globomatics-ec2 ec2-user@<publicIp>
```

## Configuración (`Pulumi.dev.yaml`)

| Clave | Descripción | Valor por defecto |
|---|---|---|
| `aws:region` | Región de AWS | `us-east-2` |
| `sshSourceCidr` | IPv4 /32 autorizada para SSH | IP administrativa |
| `instanceType` | Tipo de instancia | `t3.micro` |
| `keyName` | Key pair existente en AWS | `key-globomatics-lab` |
| `amiParameter` | Parámetro SSM de la AMI | AL2023 kernel 6.18 |
| `vpcId` / `subnetId` | Opcionales; si se omiten usa la VPC por defecto | — |

Para usar la VPC creada por OpenTofu, agrega en `Pulumi.dev.yaml`:

```yaml
  globomatics-vm:vpcId: <id-de-vpc-globomatics-lab>
  globomatics-vm:subnetId: <id-de-subnet-publica-globomatics-lab>
```

## Destruir solo la VM de Pulumi

```powershell
python ..\scripts\pulumi-session.py --aws-profile proyecto destroy
```

Esto **no** afecta los recursos administrados por OpenTofu. El bucket de estado
compartido tampoco se elimina.

## Notas de trabajo en equipo

- No copies ni muevas el estado a mano. Todos usan el mismo backend S3.
- Actualiza el código desde Git antes de ejecutar `preview`/`up`.
- No ejecutes `pulumi cancel` ni desbloquees mientras otro compañero esté
  trabajando.
- `Pulumi.dev.yaml` no contiene secretos. Si algún día agregas uno, usa
  `pulumi config set --secret`.
