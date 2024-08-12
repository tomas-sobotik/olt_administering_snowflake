------------------------------------------- 03 database roles ---------------------------------------

--create account level roles for granting db roles to them

use role securityadmin;

create or replace role developer;
create or replace role analyst;

--grant roles to my user
grant role developer to user tomas;
grant role analyst to user tomas;

--check db roles in share
use role accountadmin;
show database roles in database sample_share;

--grant individual db roles to individual account roles to get granular access to objects inside share
grant database role sample_share.share_provider1 to role developer;

grant database role sample_share.share_provider2 to role analyst;

--check what kind of access each role got
use role developer;

use role analyst;
