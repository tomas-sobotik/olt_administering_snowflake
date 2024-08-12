--------------------------------------01 authentication ---------------------------------
--private & public key generation

--1. Let’s check if our user does not have assigned some key by performing desc user <my_username>

desc user tomas;

--key generation
--private
--openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 des3 -inform PEM -out rsa_key.p8

--public key:
--openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub

--assign public key to the user
 Alter user tomas set rsa_public_key = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsliFCYJ1WTRc1tU7XERe
WxYmJkn0FseOMwy3Vh8VbdZ3hXDAQGwqY9FdSXcSxJEqFYTM/D8dofmQLGPPPELX
QNYorbiZjD33HVagIhhfP72IdmYNXrzIvNRy+X7hadrMZpXRGmHqeM6UyevKHN9w
8OSWKKMXRGB6+TgzgGNty/izk4fVS+yFrCFnP0D6OAysJveODLfNt7Ux+16SfI+y
/iioXMWHeNGW/DOU3vbazIS86wev6YudiEg/ZGhD74iezsYlTFUW5DXeWhJ3NQ6w
EoSgrNli2ew93l0ynAYKwbmYyVdeHgN6nNjfC8/3JDlA/sywI4APTbb5YVKfjO7l
OQIDAQAB';

--can you guess how to do a key rotation?


--how to monitor users without MFA - use login history view for that or new trust center feature
select * from snowflake.ACCOUNT_USAGE.LOGIN_HISTORY
;

use role accountadmin;
--authentication policy to enforce MFA
CREATE AUTHENTICATION POLICY mfa_enforcement_policy
  MFA_ENROLLMENT = 'REQUIRED'
  MFA_AUTHENTICATION_METHODS = ('PASSWORD');

--set to account
ALTER ACCOUNT SET AUTHENTICATION POLICY mfa_enforcement_policy;
--unset
ALTER ACCOUNT UNSET AUTHENTICATION POLICY;

--set to individual user
ALTER USER john SET AUTHENTICATION POLICY mfa_enforcement_policy;

--------------------------------------02 authorization ---------------------------------
--first we need some DB, schema and tables to work on. Let's use Snowflake sample data for it
--create DB, schema, table and stage. We will replicate those objects

---> set the Role
USE ROLE accountadmin;

---> set the Warehouse
USE WAREHOUSE compute_wh;

---> create the Tasty Bytes Database
CREATE OR REPLACE DATABASE tasty_bytes_sample_data;

---> create the Raw POS (Point-of-Sale) Schema
CREATE OR REPLACE SCHEMA tasty_bytes_sample_data.raw_pos;

---> create the Raw Menu Table
CREATE OR REPLACE TABLE tasty_bytes_sample_data.raw_pos.menu
(
    menu_id NUMBER(19,0),
    menu_type_id NUMBER(38,0),
    menu_type VARCHAR(16777216),
    truck_brand_name VARCHAR(16777216),
    menu_item_id NUMBER(38,0),
    menu_item_name VARCHAR(16777216),
    item_category VARCHAR(16777216),
    item_subcategory VARCHAR(16777216),
    cost_of_goods_usd NUMBER(38,4),
    sale_price_usd NUMBER(38,4),
    menu_item_health_metrics_obj VARIANT
);

---> confirm the empty Menu table exists
SELECT * FROM tasty_bytes_sample_data.raw_pos.menu;

---> create the Stage referencing the Blob location and CSV File Format
CREATE OR REPLACE STAGE tasty_bytes_sample_data.public.blob_stage
url = 's3://sfquickstarts/tastybytes/'
file_format = (type = csv);

---> query the Stage to find the Menu CSV file
LIST @tasty_bytes_sample_data.public.blob_stage/raw_pos/menu/;

---> copy the Menu file into the Menu table
COPY INTO tasty_bytes_sample_data.raw_pos.menu
FROM @tasty_bytes_sample_data.public.blob_stage/raw_pos/menu/;

---> how many rows are in the table?
SELECT COUNT(*) AS row_count FROM tasty_bytes_sample_data.raw_pos.menu;

--adding a view on top of table - will need it in one of the future exercises
select * from menu;

create or replace view menu_view as
select
    menu_id,
    menu_type,
    menu_item_id,
    menu_item_name,
    item_category,
    sale_price_usd
from menu;

--check the view
select * from menu_view;

--creation of custom role hierarchy
use role securityadmin;

create or replace role ANALYST;
grant usage on database tasty_bytes_sample_data to role analyst;
grant usage on schema tasty_bytes_sample_data.raw_pos to role analyst;
grant select on table tasty_bytes_sample_data.raw_pos.menu to role analyst;
grant usage on warehouse compute_wh to role analyst;

create or replace role DEVELOPER;
grant role ANALYST to role DEVELOPER;
grant all on database tasty_bytes_sample_data to role developer;
grant all on schema tasty_bytes_sample_data.raw_pos to role developer;
grant role developer to role SYSADMIN;

grant select on future tables in schema raw_pos to role DEVELOPER;


use role analyst;
create table tmp as select * from menu where 1 = 0;

use role developer;

create table tmp as select * from menu where 1 = 0;
drop table tmp;


--granting secondary roles - need to run it every time you login
USE SECONDARY ROLES all;

use role securityadmin;
--better to add it directly into user parameters
alter user tomas set default_secondary_roles = ('all');

--check assigned secondary roles - empty for us
select CURRENT_SECONDARY_ROLES();

--------------------------------------03 database roles - running on different account ---------------------------
--create one more table and view so we can choose from multiple objects what to add into data share
use role sysadmin;
create or replace table landing_table (
id number,
value varchar,
created timestamp);

--secure view - because of data sharing
create or replace secure view landing_view as
select
  id,
  value
from landing_table;

--creating 2 db roles role for acessing DB objects
create database role tasty_bytes_sample_data.share_provider1;

create database role tasty_bytes_sample_data.share_provider2;

--grant usage on db, schema and table we want to share
grant usage on database tasty_bytes_sample_data to database role share_provider1;

grant usage on database tasty_bytes_sample_data to database role share_provider2;

grant usage on schema tasty_bytes_sample_data.raw_pos to database role share_provider1;
grant usage on schema tasty_bytes_sample_data.raw_pos to database role share_provider2;

--grant access to different objects to different roles
grant select on table tasty_bytes_sample_data.raw_pos.menu to database role share_provider1;

--grant access to different objects to different roles
grant select on table tasty_bytes_sample_data.raw_pos.landing_table to database role share_provider2;
grant select on table tasty_bytes_sample_data.raw_pos.landing_view to database role share_provider2;

--create empty share
use role accountadmin;
create share s_tasty_share;

--grant usage on database to include it into the share
grant usage on database tasty_bytes_sample_data to share s_tasty_share;

--grant roles to share
grant database role share_provider1 to share s_tasty_share;

grant database role share_provider2 to share s_tasty_share;

--check the shares
show shares;

--adding our other account to the share
alter share s_tasty_share add accounts = wzfcleo.azure_replica;

--------------------------------------04 privileges ----------------------------------

--granting privileges we already did when creating DEVELOPER and ANALYST roles
--let's check how we can review the privileges setup
/*
Our tasks:

List all users and roles who has granted roles ANALYST and DEVELOPER
List all privileges granted no role DEVELOPER
List all privileges granted on schema RAW_POS
List all privileges granted no table MENU
List all privileges granted to role DEVELOPER
List all privileges granted to your user
Check what are future grants in in schema RAW_POS
Check all privileges on schema RAW_POS and filter the result only for ANALYST role
Grant INSERT on MENU table to role ANALYST and then REVOKE it


*/


--how to check privilege setup
use role accountadmin;

--list all users and roles who has this role granted
show grants of role developer;
show grants of role analyst;

--privileges granted on the object
show grants on role developer;

show grants on schema raw_pos;
show grants on table menu;

--all privileges and roles granted to object
show grants to role developer;
show grants to user tomas;

--check future grants
show future grants in schema raw_pos;

--how to process result as a table
show grants on schema raw_pos;
select * from table(result_scan(last_query_id())) where "grantee_name" = 'ANALYST';


--revoking the privileges
--incorrect grant
grant insert on table menu to role analyst;

revoke insert on table menu from role analyst;
--check again
show grants on table menu;

--how to check in UI

--------------------------------------05 auditing user activities -----------------------

--extracting infos from direct object accessed column and filtered for stages
select d1.value:"objectDomain"::varchar objectDomain,
d1.value:"objectId"::varchar objectId,
d1.value:"stageKind"::varchar stageKind,
a.* from snowflake.account_usage.access_history a,
lateral flatten (direct_objects_accessed) d1
where
objectDomain = 'Stage';


--adding table details
select d1.value:"objectDomain"::varchar objectDomain,
d1.value:"objectId"::varchar objectId,
d1.value:"stageKind"::varchar stageKind,
d1.value:objectName::varchar stageName,
o1.value:"objectDomain"::varchar accessedObject,
a.* from snowflake.account_usage.access_history a,
lateral flatten (direct_objects_accessed) d1,
lateral flatten (objects_modified) o1
where
objectDomain = 'Stage'
and stageKind = 'External Named'
and accessedObject = 'Table';


--adding column level details
select d1.value:"objectDomain"::varchar objectDomain,
d1.value:"objectId"::varchar objectId,
d1.value:"stageKind"::varchar stageKind,
d1.value:objectName::varchar stageName,
o1.value:"objectDomain"::varchar accessedObject,
c1.value:columnName::varchar as colum_name,
a.* from snowflake.account_usage.access_history a,
lateral flatten (direct_objects_accessed) d1,
lateral flatten (objects_modified) o1,
lateral flatten (o1.value:columns) c1,
where
objectDomain = 'Stage'
and stageKind = 'External Named'
and accessedObject = 'Table';

--querying the view - be careful about case sensitivity in keys! objectDomain is not same like
--objectdomain
select d1.value:"objectDomain"::varchar objectDomain,
d1.value:"objectId"::varchar objectId,
d1.value:"stageKind"::varchar stageKind,
b1.value:objectName::varchar table_name,
a.* from snowflake.account_usage.access_history a,
lateral flatten (direct_objects_accessed) d1,
lateral flatten (base_objects_accessed) b1
where
objectDomain = 'View'
and b1.value:objectDomain = 'Table'
and table_name = 'TASTY_BYTES_SAMPLE_DATA.RAW_POS.MENU';

--finding all tables access by user x
with

access_history_flattened as (
    select
        access_history.query_id,
        access_history.query_start_time,
        access_history.user_name,
        objects_accessed.value:objectName::text as object_name,
        objects_accessed.value:objectDomain::text as object_domain,
        objects_accessed.value:columns as columns_array
    from snowflake.account_usage.access_history,
        lateral flatten(access_history.base_objects_accessed) as objects_accessed
    where
        access_history.query_start_time > current_date - 30
)
select
    object_name,
    count(*) as number_of_times_accessed
from access_history_flattened
where
    user_name='TOMAS'
    and object_domain='Table'
group by 1
order by 2 desc;

--who has modified the table? - some data in objects modified array
with
access_history_flattened as (
    select
        access_history.query_id,
        access_history.query_start_time,
        access_history.user_name,
        objects_modified.value:objectName::text as object_name,
        objects_modified.value:objectDomain::text as object_domain
    from snowflake.account_usage.access_history,
        lateral flatten(access_history.objects_modified) as objects_modified
    where
        access_history.query_start_time > current_date - 30
)
select
    query_id,
    user_name,
    query_start_time
from access_history_flattened
where
    object_domain='Table'
    and object_name='TASTY_BYTES_SAMPLE_DATA.RAW_POS.MENU'
;

--the most accessed columns in table X
with
access_history_flattened as (
    select
        access_history.query_id,
        access_history.query_start_time,
        access_history.user_name,
        objects_accessed.value:objectName::text as object_name,
        objects_accessed.value:objectDomain::text as object_domain,
        objects_accessed.value:columns as columns_array
    from snowflake.account_usage.access_history, lateral flatten(access_history.base_objects_accessed) as objects_accessed
    where
        access_history.query_start_time > current_date - 30
),

access_history_flattened_columns as (
    select
        access_history_flattened.* exclude columns_array,
        columns_accessed.value:columnName::text as column_name
    from access_history_flattened, lateral flatten(access_history_flattened.columns_array) as columns_accessed
)
select
    column_name,
    count(*) as number_of_times_accessed
from access_history_flattened_columns
where
    object_domain='Table'
    and object_name='TASTY_BYTES_SAMPLE_DATA.RAW_POS.MENU'
group by 1
order by 2 desc;

/* other possible use cases
    - identify unused tables/views
    - find all users who has accessed specified object
    - find all tables accessed in the schema
    - ...
*/

--------------------------------------06 resource monitors ---------------------------

--resource monitors and their assignment to warehouses with monthly frequency (default value)
use role accountadmin;
CREATE OR REPLACE RESOURCE MONITOR rm_user_queries
  WITH CREDIT_QUOTA = 50
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY --notifications are sent to accountadmins
           ON 98 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;

show resource monitors;

--assigning to warehouse
show warehouses;

alter warehouse compute_wh
set resource_monitor = rm_user_queries;

--account level monitor
CREATE RESOURCE MONITOR rm_account WITH CREDIT_QUOTA=1000
  TRIGGERS ON 100 PERCENT DO SUSPEND;

ALTER ACCOUNT SET RESOURCE_MONITOR = rm_account;

--where to find them in UI: Admin -> Cost Management -> Resource Monitor


--Adding non admins to receive notifications
CREATE OR REPLACE USER joe;
grant role developer to user joe;

--joe needs to verify his email address to receive notifications (User profile)

--add joe to resource monitor - only wh level
alter resource monitor rm_user_queries
set notify_users = (JOE);

alter user joe set email = 'joe@gmail.com';

alter user joe set email = '';

--------------------------------------07 warehouse configuration -----------------------------

use role SYSADMIN;
--creating single VWH with basic params
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH WITH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- Creating a multicluster warehouse with basic params
CREATE WAREHOUSE IF NOT EXISTS MULTI_COMPUTE_WH WITH
  WAREHOUSE_SIZE = SMALL
  MIN_CLUSTER_COUNT = 1
  MAX_CLUSTER_COUNT = 3
  SCALING_POLICY = ECONOMY ---overwritting the default STANDARD policy
  AUTO_SUSPEND = 180
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;


--find out the current value of timeout parameter for compute_wh
describe warehouse compute_wh; --no
show warehouses like 'compute_wh'; --no
show parameters for warehouse compute_wh; --yes

describe warehouse multi_compute_wh; --no
show warehouses like 'multi_compute_wh'; --no
show parameters for warehouse multi_compute_wh; --yes

--modify the parameter for compute_wh
alter warehouse compute_wh set STATEMENT_TIMEOUT_IN_SECONDS = 3600;

--other places where query timeouts could be set

--session
show parameters for session;
alter session set STATEMENT_TIMEOUT_IN_SECONDS = 3600;

--account
show parameters for account;
use role accountadmin;
alter account set STATEMENT_TIMEOUT_IN_SECONDS = 172800;

--different settings per wh, session, account? Snowlfake will enforce the lowest available level: warehouse > session > account

--setting the parameter when creating the warehouse
use role sysadmin;
CREATE OR REPLACE WAREHOUSE COMPUTE_WH2
warehouse_size = 'SMALL'
statement_timeout_in_seconds = 3600;

--resource monitors and their assignment to warehouses with monthly frequency (default value)
use role accountadmin;
CREATE OR REPLACE RESOURCE MONITOR rm_small_compute
  WITH CREDIT_QUOTA = 20
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY --notifications are sent to accountadmins
           ON 98 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;

show resource monitors;

--assigning to warehouse
alter warehouse compute_wh2
set resource_monitor = rm_small_compute;

--check the settings
show warehouses;


--------------------------------------08 database replication ---------------------------

--let's do the replication now. We will be creating failover group to be able to selectalso account objects. Replication group can replicate only db or share

--create sample role to test replication of account objects
CREATE OR REPLACE role tester;

grant role tester to role sysadmin;
grant usage on warehouse compute_wh to role tester;

use role orgadmin;

--find out current org name
select CURRENT_ORGANIZATION_NAME();

--enable replication for both our accounts
SELECT SYSTEM$GLOBAL_ACCOUNT_SET_PARAMETER('wzfcleo.xt95060','ENABLE_ACCOUNT_DATABASE_REPLICATION', 'true'); --returns success

SELECT SYSTEM$GLOBAL_ACCOUNT_SET_PARAMETER('wzfcleo.azure_replica','ENABLE_ACCOUNT_DATABASE_REPLICATION', 'true'); --returns success

use role accountadmin;

drop failover group my_failover_group;

--create failover group
CREATE FAILOVER GROUP my_failover_group
  OBJECT_TYPES = ROLES, WAREHOUSES, DATABASES
  ALLOWED_DATABASES = tasty_bytes_sample_data
  ALLOWED_ACCOUNTS = wzfcleo.azure_replica
  REPLICATION_SCHEDULE = '10 MINUTE';

--check the group
show failover groups;

--monitoring of the replication -> Snowsight: Admin -> Accounts -> Replication

--sql
SELECT phase_name, start_time, end_time, progress, details
  FROM TABLE(INFORMATION_SCHEMA.REPLICATION_GROUP_REFRESH_PROGRESS('my_failover_group'));

  show grants on failover group my_failover_group;

  grant monitor on failover group my_failover_group to role accountadmin;
