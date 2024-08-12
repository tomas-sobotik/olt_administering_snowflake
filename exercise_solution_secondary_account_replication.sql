------------------------------------------- 08 database replication ---------------------------------------
--grant orgadmin to my user
USE ROLE accountadmin;

-- Grant the ORGADMIN role to a user
GRANT ROLE orgadmin TO USER tomas;

--create failover group as replica of failover group from primary account
CREATE FAILOVER GROUP my_failover_group
    AS REPLICA OF wzfcleo.xt95060.my_failover_group;


--check the groups
show failover groups;

--need to add a global identifier to roles created outside of replication = system roles
SELECT SYSTEM$LINK_ACCOUNT_OBJECTS_BY_NAME('my_failover_group');

--manual refresh of failover group - not needed now as it runs automatically when we created secondary failover group
ALTER FAILOVER GROUP my_failover_group REFRESH;

show grants on failover group my_failover_group;

--grant monitor of failover group to role doing the replication to see monitoring data
grant monitor on failover group my_failover_group to role accountadmin;


--suspend replication
alter failover group my_failover_group suspend;
