import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

const config = new pulumi.Config();

// La region se toma de `aws:region` en Pulumi.dev.yaml.
const instanceType = config.get("instanceType") ?? "t3.micro";
const sshSourceCidr = config.require("sshSourceCidr");
const keyName = config.get("keyName") ?? "key-globomatics-lab";
const amiParameter =
  config.get("amiParameter") ??
  "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.18-x86_64";

// VPC/subred: por defecto usa la VPC por defecto de la cuenta. Si el equipo
// prefiere integrarse con la VPC de OpenTofu, basta con definir vpcId/subnetId
// en Pulumi.dev.yaml.
const configuredVpcId = config.get("vpcId");
const configuredSubnetId = config.get("subnetId");

const vpcId: pulumi.Output<string> = configuredVpcId
  ? pulumi.output(configuredVpcId)
  : aws.ec2.getVpcOutput({ default: true }).id;

const subnetId: pulumi.Output<string> = configuredSubnetId
  ? pulumi.output(configuredSubnetId)
  : aws.ec2
      .getSubnetsOutput({ filters: [{ name: "vpc-id", values: [vpcId] }] })
      .ids.apply((ids) => ids[0]);

const ami = aws.ssm.getParameterOutput({ name: amiParameter });

const securityGroup = new aws.ec2.SecurityGroup("pulumi-vm-sg", {
  name: "pulumi-vm-sg",
  description:
    "SSH administrativo, web publica y salida para la VM de laboratorio Globomatics",
  vpcId,
  ingress: [
    {
      description: "SSH desde la IP administrativa",
      protocol: "tcp",
      fromPort: 22,
      toPort: 22,
      cidrBlocks: [sshSourceCidr],
    },
    {
      description: "HTTP publico",
      protocol: "tcp",
      fromPort: 80,
      toPort: 80,
      cidrBlocks: ["0.0.0.0/0"],
    },
    {
      description: "HTTPS publico",
      protocol: "tcp",
      fromPort: 443,
      toPort: 443,
      cidrBlocks: ["0.0.0.0/0"],
    },
  ],
  egress: [
    {
      description: "Salida para actualizaciones y configuracion",
      protocol: "-1",
      fromPort: 0,
      toPort: 0,
      cidrBlocks: ["0.0.0.0/0"],
    },
  ],
  tags: {
    Name: "pulumi-vm-sg",
    Project: "globomatics",
    ManagedBy: "Pulumi",
  },
});

const vm = new aws.ec2.Instance("pulumi-vm", {
  ami: ami.value,
  instanceType,
  subnetId,
  keyName,
  vpcSecurityGroupIds: [securityGroup.id],
  associatePublicIpAddress: true,
  metadataOptions: {
    httpEndpoint: "enabled",
    httpTokens: "required",
  },
  rootBlockDevice: {
    volumeType: "gp3",
    volumeSize: 12,
    encrypted: true,
    deleteOnTermination: true,
  },
  tags: {
    Name: "ec2-pulumi-globomatics",
    Project: "globomatics",
    Role: "pulumi-vm",
    ManagedBy: "Pulumi",
  },
});

export const publicIp = vm.publicIp;
export const privateIp = vm.privateIp;
export const instanceId = vm.id;
export const sshCommand = pulumi.interpolate`ssh -i ~/globomatics-ec2 ec2-user@${vm.publicIp}`;
