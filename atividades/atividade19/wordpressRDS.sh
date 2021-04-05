#!/bin/bash

KEY_PAIR=$1
USER_NAME=$2
PASSWORD=$3
SG_NAME="${4:-web-mysql-sg}"
PROFILE="${5:-default}"
MY_IP=$(curl -s http://checkip.amazonaws.com)
RDS_INSTANCE_NAME=scripts-$(date +"%s")

# # create security group
SG_ID=$(aws ec2 describe-security-groups --profile $PROFILE  \
    --filters Name=group-name,Values=$SG_NAME \
    --query "SecurityGroups[*].GroupId" --output text
)
if [ -z $SG_ID ]
then
    SG_ID=$(aws ec2 create-security-group --profile $PROFILE  \
        --group-name $SG_NAME --description "Ports 80, 22 and 3306" --query "GroupId" --output=text
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

if ! [[ " ${PORTS[@]} " =~ " 3306 " ]]; then
    aws ec2 authorize-security-group-ingress --profile $PROFILE --group-name $SG_NAME --protocol tcp --port 3306 --source-group=$SG_ID
fi

# run db instance
DB_INSTANCE=$(aws rds create-db-instance --profile $PROFILE \
    --db-instance-identifier $RDS_INSTANCE_NAME --engine mysql \
    --master-username $USER_NAME --master-user-password $PASSWORD \
    --allocated-storage 20 --no-publicly-accessible \
    --vpc-security-group-id $SG_ID --db-instance-class db.t2.micro
)

# wait for instance creation
DB_STATUS=
while [ "$DB_STATUS" != "available" ]
do
    echo "Criando instância de Banco de Dados no RDS..."
    sleep 30
    DB_STATUS=$(aws rds describe-db-instances --profile $PROFILE \
        --db-instance-identifier $RDS_INSTANCE_NAME --query "DBInstances[*].DBInstanceStatus" --output text
    )
done

# get instance ip
DB_ENDPOINT=$(aws rds describe-db-instances --profile $PROFILE \
    --db-instance-identifier $RDS_INSTANCE_NAME --query "DBInstances[*].Endpoint.Address" --output text
)
echo "Endpoint do RDS:" $DB_ENDPOINT

# sets environment variables
sed -i "s/^export usuario=.*/export usuario=$USER_NAME/g" user_data_client.txt
sed -i "s/^export senha=.*/export senha=$PASSWORD/g" user_data_client.txt
sed -i "s/^export server_ip=.*/export server_ip=$DB_ENDPOINT/g" user_data_client.txt

# run instance
INSTANCE_CLIENT=$(aws ec2 run-instances --profile $PROFILE \
    --image-id ami-042e8287309f5df03 --count 1 --instance-type t2.micro \
    --key-name $KEY_PAIR --security-group-ids $SG_ID --user-data file://user_data_client.txt \
    --query "Instances[*].InstanceId" --output=text
)

# clears environment variables
sed -i "s/^export usuario=.*/export usuario=/g" user_data_client.txt
sed -i "s/^export senha=.*/export senha=/g" user_data_client.txt
sed -i "s/^export server_ip=.*/export server_ip=/g" user_data_client.txt

# wait for instance creation
STATUS_CLIENT=
while [ "$STATUS_CLIENT" != "ok" ]
do
    echo "Criando servidor de Aplicação..."
    sleep 30
    STATUS_CLIENT=$(aws ec2 describe-instance-status --instance-id $INSTANCE_CLIENT --profile $PROFILE \
        --query "InstanceStatuses[0].InstanceStatus.Status" --output=text
    )
done

# get instance ip
IP_CLIENT=$(aws ec2 describe-instances --profile $PROFILE \
    --instance-id $INSTANCE_CLIENT \
    --query "Reservations[*].Instances[*].PublicIpAddress" --output=text
)
echo "IP Público do Servidor de Aplicação:" $IP_CLIENT

echo "Acesse http://$IP_CLIENT/wordpress para finalizar a configuração."
