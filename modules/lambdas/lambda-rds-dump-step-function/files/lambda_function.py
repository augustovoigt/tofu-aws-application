import os
import json
import boto3

def lambda_handler(event, context):
    # Initialize the Step Functions client
    sfn_client = boto3.client('stepfunctions')

    # Retrieve all environment variables
    db_instance_auto_minor_version_upgrade = os.environ.get('DB_INSTANCE_AUTO_MINOR_VERSION_UPGRADE')
    db_instance_backup_retention_period = os.environ.get('DB_INSTANCE_BACKUP_RETENTION_PERIOD')
    db_instance_ca_cert_identifier = os.environ.get('DB_INSTANCE_CA_CERT_IDENTIFIER')
    db_instance_class = os.environ.get('DB_INSTANCE_CLASS')
    db_instance_copy_tags_to_snapshot = os.environ.get('DB_INSTANCE_COPY_TAGS_TO_SNAPSHOT')
    db_instance_delete_protection = os.environ.get('DB_INSTANCE_DELETE_PROTECTION')
    db_instance_identifier_destination = os.environ.get('DB_INSTANCE_IDENTIFIER_DESTINATION')
    db_instance_identifier_source = os.environ.get('DB_INSTANCE_IDENTIFIER_SOURCE')
    db_instance_monitoring_interval = os.environ.get('DB_INSTANCE_MONITORING_INTERVAL')
    db_instance_monitoring_role_arn = os.environ.get('DB_INSTANCE_MONITORING_ROLE_ARN')
    db_instance_performance_insights_enabled = os.environ.get('DB_INSTANCE_PERFORMANCE_INSIGHTS_ENABLED')
    db_instance_multiaz = os.environ.get('DB_INSTANCE_MULTIAZ')
    db_instance_name = os.environ.get('DB_INSTANCE_NAME')
    db_instance_og = os.environ.get('DB_INSTANCE_OG')
    db_instance_pg = os.environ.get('DB_INSTANCE_PG')
    db_instance_publicly_accessible = os.environ.get('DB_INSTANCE_PUBLICLY_ACCESSIBLE')
    db_instance_s3_integration_role_arn = os.environ.get('DB_INSTANCE_S3_INTEGRATION_ROLE_ARN')
    db_instance_sg = json.loads(os.environ.get('DB_INSTANCE_SG'))
    db_instance_sql_updates_statements = os.environ.get('DB_INSTANCE_SQL_UPDATES_STATEMENTS')
    db_instance_storage_type = os.environ.get('DB_INSTANCE_STORAGE_TYPE')
    db_instance_subnet_id = os.environ.get('DB_INSTANCE_SUBNET_ID')
    db_instance_tags = json.loads(os.environ.get('DB_INSTANCE_TAGS'))
    redis_base_key = os.environ.get('REDIS_BASE_KEY')
    redis_primary_endpoint_address = os.environ.get('REDIS_PRIMARY_ENDPOINT_ADDRESS')
    step_function_arn = os.environ.get('DUMP_RDS_STEP_FUNCTIONS_ARN')
    rds_users = json.loads(os.environ.get('RDS_USERS'))

    # Define the payload for the Step Function execution
    payload = {
        "db_instance_auto_minor_version_upgrade": db_instance_auto_minor_version_upgrade,
        "db_instance_backup_retention_period" : db_instance_backup_retention_period,
        "db_instance_ca_cert_identifier": db_instance_ca_cert_identifier,
        "db_instance_class": db_instance_class,
        "db_instance_copy_tags_to_snapshot": db_instance_copy_tags_to_snapshot,
        "db_instance_delete_protection": db_instance_delete_protection,
        "db_instance_identifier_destination": db_instance_identifier_destination,
        "db_instance_identifier_source": db_instance_identifier_source,
        "db_instance_monitoring_interval": db_instance_monitoring_interval,
        "db_instance_monitoring_role_arn": db_instance_monitoring_role_arn,
        "db_instance_performance_insights_enabled": db_instance_performance_insights_enabled,
        "db_instance_multiaz": db_instance_multiaz,
        "db_instance_name": db_instance_name,
        "db_instance_og": db_instance_og,
        "db_instance_pg": db_instance_pg,
        "db_instance_publicly_accessible": db_instance_publicly_accessible,
        "db_instance_s3_integration_role_arn": db_instance_s3_integration_role_arn,
        "db_instance_sg": db_instance_sg,
        "db_instance_sql_updates_statements": db_instance_sql_updates_statements,
        "db_instance_storage_type": db_instance_storage_type,
        "db_instance_subnet_id": db_instance_subnet_id,
        "db_instance_tags": db_instance_tags,
        "redis_base_key": redis_base_key,
        "redis_primary_endpoint_address": redis_primary_endpoint_address,
        "rds_users": rds_users
    }
    
    # Execute the Step Function
    try:
        response = sfn_client.start_execution(
            stateMachineArn=step_function_arn,
            input=json.dumps(payload)
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Step Function execution started successfully',
                'executionArn': response['executionArn']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Failed to start Step Function execution',
                'error': str(e)
            })
        }