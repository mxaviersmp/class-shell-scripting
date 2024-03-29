#!/bin/bash
# Correção: 1,0. Use o nginx ou o apache nas próximas atividades.

KEY_PAIR=$1
SG_NAME="${2:-$web-sg}"
PROFILE="${3:-default}"
MY_IP=$(curl -s http://checkip.amazonaws.com)

# create security group
SG_ID=$(aws ec2 describe-security-groups --profile $PROFILE  \
    --filters Name=group-name,Values=$SG_NAME \
    --query "SecurityGroups[*].GroupId" --output text
)
if [ -z $SG_ID ]
then
    SG_ID=$(aws ec2 create-security-group --profile $PROFILE  \
        --group-name $SG_NAME --description "Ports 80 and 22" --query "GroupId" --output=text
    )
fi

# add permissions to security group
PORTS=$(aws ec2 describe-security-groups --profile $PROFILE  \
    --filters Name=group-name,Values=$SG_NAME \
    --query "SecurityGroups[*].IpPermissions[*].FromPort" --output text | sed 's/\t/:/g'
)
PORTS=(${PORTS//:/ })

if ! [[ " ${PORTS[@]} " =~ " 80 " ]]; then
    aws ec2 authorize-security-group-ingress --profile $PROFILE --group-name $SG_NAME --protocol tcp --port 80 --cidr 0.0.0.0/0
fi

if ! [[ " ${PORTS[@]} " =~ " 22 " ]]; then
    aws ec2 authorize-security-group-ingress --profile $PROFILE --group-name $SG_NAME --protocol tcp --port 22 --cidr $MY_IP/32
fi

# run instance
INSTANCE=$(aws ec2 run-instances --profile $PROFILE \
    --image-id ami-042e8287309f5df03 --count 1 --instance-type t2.micro \
    --key-name $KEY_PAIR --security-group-ids $SG_ID --user-data file://user_data.txt \
    --query "Instances[*].InstanceId" --output=text
)

# wait for instance creation
STATUS=
while [ "$STATUS" != "running" ]
do
    echo "Criando servidor de Monitoramento em CRON..."
    sleep 30
    STATUS=$(aws ec2 describe-instance-status --instance-id $INSTANCE --profile $PROFILE \
        --query "InstanceStatuses[0].InstanceState.Name" --output=text
    )
done
echo 'Instância em estado "running"'

# get instance ip
IP=$(aws ec2 describe-instances --profile $PROFILE \
    --instance-id $INSTANCE \
    --query "Reservations[*].Instances[*].PublicIpAddress" --output=text
)
echo Acesse: http://$IP/
