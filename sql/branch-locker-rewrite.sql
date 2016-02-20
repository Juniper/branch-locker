
-- Copyright (c) 2016, Juniper Networks Inc.
-- All rights reserved.
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--     http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Setup Permissions
-- REVOKE ALL PRIVILEGES ON DATABASE blr_dev FROM PUBLIC CASCADE;
-- REVOKE ALL PRIVILEGES ON SCHEMA public FROM PUBLIC CASCADE;
-- GRANT CONNECT ON DATABASE blr_dev TO PUBLIC;

CREATE ROLE blr_w WITH LOGIN;

-- Create Language support
CREATE LANGUAGE plpgsql;

-- Drop Schema
DROP SCHEMA blr CASCADE;

-- Create Schema
CREATE SCHEMA blr AUTHORIZATION blr_w

-- Create Tables.
CREATE TABLE bl_user(
    id   SERIAL UNIQUE PRIMARY KEY,
    name text UNIQUE
)

CREATE TABLE bl_group(
    id       SERIAL UNIQUE PRIMARY KEY,
    name     text UNIQUE,
    is_admin boolean DEFAULT FALSE
)

CREATE TABLE bl_repository(
    id   SERIAL UNIQUE PRIMARY KEY,
    name text
)

CREATE TABLE bl_path(
    id   SERIAL UNIQUE PRIMARY KEY,
    name text
)

CREATE TABLE bl_location(
    id            SERIAL UNIQUE PRIMARY KEY,
    path_id       integer,
    repository_id integer
)

CREATE TABLE bl_lock(
    id          SERIAL UNIQUE PRIMARY KEY,
    name        text,
    message     text,
    is_active   boolean DEFAULT TRUE,
    is_open     boolean DEFAULT FALSE,
    -- For Phase 1 -- Remove 4 lines for Phase 2
    old_lock    integer,
    old_release integer,
    grouped     text,
    is_closed   boolean DEFAULT FALSE
)

CREATE TABLE bl_enforcement(
    id           SERIAL UNIQUE PRIMARY KEY,
    name         text,
    is_enabled   boolean DEFAULT FALSE
)

CREATE TABLE bl_audit_event(
    id                   SERIAL UNIQUE PRIMARY KEY,
    table_name           text NOT NULL,
    user_name            text,
    action_timestamp     timestamp WITH time zone NOT NULL DEFAULT now(),
    action               text,
    old_data             text,
    new_data             text,
    audit_transaction_id integer
)

CREATE TABLE bl_audit_transaction(
    id               SERIAL UNIQUE PRIMARY KEY,
    api_key_id       integer,
    as_user_id       integer,
    data_dump        text,
    start_timestamp  timestamp WITH time zone NOT NULL DEFAULT now(),
    end_timestamp    timestamp WITH time zone
)

CREATE TABLE bl_api_key(
    id                   SERIAL UNIQUE PRIMARY KEY,
    api_key              text NOT NULL UNIQUE,
    user_id              integer,
    can_impersonate      boolean DEFAULT FALSE,
    creation_timestamp   timestamp WITH time zone NOT NULL DEFAULT now(),
    expiration_timestamp timestamp WITH time zone DEFAULT NULL
)

CREATE TABLE bl_link_user_to_group(
    id       SERIAL UNIQUE PRIMARY KEY,
    user_id  integer,
    group_id integer,
    UNIQUE(user_id, group_id)
)

CREATE TABLE bl_link_location_to_lock(
    id          SERIAL UNIQUE PRIMARY KEY,
    location_id integer,
    lock_id     integer,
    UNIQUE(location_id, lock_id)
)

CREATE TABLE bl_link_enforcement_to_lock(
    id             SERIAL UNIQUE PRIMARY KEY,
    enforcement_id integer,
    lock_id        integer,
    UNIQUE(enforcement_id, lock_id)
)

CREATE TABLE bl_link_user_to_enforcement_can_enable(
    id             SERIAL UNIQUE PRIMARY KEY,
    user_id        integer,
    enforcement_id integer,
    UNIQUE(user_id, enforcement_id)
)

CREATE TABLE bl_link_user_to_enforcement_can_edit(
    id             SERIAL UNIQUE PRIMARY KEY,
    user_id        integer,
    enforcement_id integer,
    UNIQUE(user_id, enforcement_id)
)

CREATE TABLE bl_link_user_to_enforcement_is_allowed(
    id             SERIAL UNIQUE PRIMARY KEY,
    user_id        integer,
    enforcement_id integer,
    UNIQUE(user_id, enforcement_id)
)

CREATE TABLE bl_link_pr_to_enforcement_is_allowed(
    id             SERIAL UNIQUE PRIMARY KEY,
    pr_number      integer,
    enforcement_id integer,
    UNIQUE(pr_number, enforcement_id)
);

-- Create Functions
CREATE OR REPLACE FUNCTION get_connection_variable(arg_key text) RETURNS text AS $$
BEGIN
    IF EXISTS (SELECT * FROM information_schema.tables WHERE table_name = 'connection_variables') THEN
        RETURN (SELECT value FROM connection_variables WHERE connection_variables.key = arg_key);
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION set_connection_variable(arg_key text, arg_value text) RETURNS text AS $$
BEGIN
    IF EXISTS (SELECT * FROM information_schema.tables WHERE table_name = 'connection_variables') THEN
        IF EXISTS (SELECT value FROM connection_variables WHERE key = arg_key) THEN
            UPDATE connection_variables
            SET    value = arg_value
            WHERE  key   = arg_key;
        ELSE
            INSERT INTO connection_variables (key, value)
            VALUES (arg_key, arg_value);
        END IF;
    ELSE
        CREATE TEMP TABLE connection_variables (key text, value text);
        INSERT INTO connection_variables (key, value)
        VALUES (arg_key, arg_value);
    END IF;

    RETURN (
        SELECT value
        FROM   connection_variables
        WHERE  key = arg_key
    );
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION blr.at_started_func() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        PERFORM set_connection_variable('audit_transaction_id'::TEXT, NEW.id::TEXT);
        RETURN NEW;
    ELSE
        RETURN NULL;
    END IF;
 
EXCEPTION
    WHEN data_exception THEN
        RAISE WARNING '[BLR.AT_STARTED_FUNC] - UDF ERROR [DATA EXCEPTION] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
    WHEN unique_violation THEN
        RAISE WARNING '[BLR.AT_STARTED_FUNC] - UDF ERROR [UNIQUE] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE WARNING '[BLR.AT_STARTED_FUNC] - UDF ERROR [OTHER] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION blr.if_modified_func() RETURNS TRIGGER AS $$
DECLARE
    v_old_data TEXT;
    v_new_data TEXT;
    i_audit_transaction_id INTEGER;
BEGIN
    i_audit_transaction_id := get_connection_variable('audit_transaction_id')::INTEGER;
    IF (get_connection_variable('audit_transaction_id') IS NULL) THEN
        INSERT INTO blr.bl_audit_transaction (api_key_id, as_user_id) VALUES (1, 1);
    END IF;

    UPDATE blr.bl_audit_transaction
    SET    end_timestamp = now()
    WHERE  id = i_audit_transaction_id;

    IF (TG_OP = 'UPDATE') THEN
        v_old_data := ROW(OLD.*);
        v_new_data := ROW(NEW.*);
        INSERT INTO blr.bl_audit_event (
            table_name,
            user_name,
            action,
            old_data,
            new_data,
            audit_transaction_id
        ) VALUES (
            TG_TABLE_NAME::TEXT,
            session_user::TEXT,
            TG_OP,
            v_old_data,
            v_new_data,
            i_audit_transaction_id
        );
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        v_old_data := ROW(OLD.*);
        INSERT INTO blr.bl_audit_event (
            table_name,
            user_name,
            action,
            old_data,
            audit_transaction_id
        ) VALUES (
            TG_TABLE_NAME::TEXT,
            session_user::TEXT,
            TG_OP,
            v_old_data,
            i_audit_transaction_id
        );
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        v_new_data := ROW(NEW.*);
        INSERT INTO blr.bl_audit_event (
            table_name,
            user_name,
            action,
            new_data,
            audit_transaction_id
        ) VALUES (
            TG_TABLE_NAME::TEXT,
            session_user::TEXT,
            TG_OP,
            v_new_data,
            i_audit_transaction_id
        );
        RETURN NEW;
    ELSE
        RAISE WARNING '[BLR.IF_MODIFIED_FUNC] - Other action occurred: %, at %',TG_OP,now();
        RETURN NULL;
    END IF;
 
EXCEPTION
    WHEN data_exception THEN
        RAISE WARNING '[BLR.IF_MODIFIED_FUNC] - UDF ERROR [DATA EXCEPTION] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
    WHEN unique_violation THEN
        RAISE WARNING '[BLR.IF_MODIFIED_FUNC] - UDF ERROR [UNIQUE] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE WARNING '[BLR.IF_MODIFIED_FUNC] - UDF ERROR [OTHER] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION blr.commacat(acc text, instr text) RETURNS text AS $$
  BEGIN
    IF acc IS NULL OR acc = '' THEN
      RETURN instr;
    ELSIF instr IS NULL OR instr = '' THEN
      RETURN acc;
    ELSE
      RETURN acc || ', ' || instr;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE AGGREGATE blr.commacat_all(
  basetype    = text,
  sfunc       = blr.commacat,
  stype       = text,
  initcond    = ''
);

CREATE OR REPLACE FUNCTION gate_keepers(blr.bl_lock) RETURNS text AS $$
    SELECT
        blr.commacat_all(DISTINCT blr.bl_user.name) AS gate_keepers

    FROM blr.bl_user
    LEFT JOIN blr.bl_link_enforcement_to_lock ON
        blr.bl_link_enforcement_to_lock.lock_id = $1.id

    LEFT JOIN blr.bl_enforcement ON
        blr.bl_link_enforcement_to_lock.enforcement_id = blr.bl_enforcement.id

    LEFT JOIN blr.bl_link_user_to_enforcement_can_edit ON
        blr.bl_link_user_to_enforcement_can_edit.enforcement_id = blr.bl_enforcement.id

    WHERE blr.bl_link_user_to_enforcement_can_edit.user_id = blr.bl_user.id

    GROUP BY $1.id;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION allowed_users(blr.bl_lock) RETURNS text AS $$
    SELECT
        blr.commacat_all(DISTINCT blr.bl_user.name) AS allowed_users

    FROM blr.bl_user
    LEFT JOIN blr.bl_link_enforcement_to_lock ON
        blr.bl_link_enforcement_to_lock.lock_id = $1.id

    LEFT JOIN blr.bl_enforcement ON
        --blr.bl_enforcement.is_enabled = TRUE -- For Phase 2
        blr.bl_link_enforcement_to_lock.enforcement_id = blr.bl_enforcement.id

    LEFT JOIN blr.bl_link_user_to_enforcement_is_allowed ON
        blr.bl_link_user_to_enforcement_is_allowed.enforcement_id = blr.bl_enforcement.id

    WHERE blr.bl_link_user_to_enforcement_is_allowed.user_id = blr.bl_user.id

    GROUP BY $1.id;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION allowed_prs(blr.bl_lock) RETURNS text AS $$
    SELECT
        blr.commacat_all(DISTINCT cast(blr.bl_link_pr_to_enforcement_is_allowed.pr_number AS text)) AS allowed_prs

    FROM blr.bl_link_pr_to_enforcement_is_allowed
    LEFT JOIN blr.bl_link_enforcement_to_lock ON
        blr.bl_link_enforcement_to_lock.lock_id = $1.id

    LEFT JOIN blr.bl_enforcement ON
        --blr.bl_enforcement.is_enabled = TRUE -- For Phase 2
        blr.bl_link_enforcement_to_lock.enforcement_id = blr.bl_enforcement.id

    WHERE blr.bl_link_pr_to_enforcement_is_allowed.enforcement_id = blr.bl_enforcement.id

    GROUP BY $1.id;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION status(blr.bl_lock) RETURNS text AS $$
    SELECT
        CASE WHEN $1.is_open = TRUE THEN 'open'
             WHEN $1.is_closed = TRUE THEN 'closed'
             --WHEN $1.allowed_users IS NULL AND $1.allowed_prs IS NULL THEN 'closed' -- For Phase 2
             ELSE 'restricted'
        END AS status;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION state(blr.bl_lock) RETURNS text AS $$
    SELECT
        CASE WHEN $1.is_active = TRUE THEN 'Active'
             ELSE 'EOL'
        END AS state;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION allowed_users(blr.bl_enforcement) RETURNS text AS $$
    SELECT
        blr.commacat_all(DISTINCT blr.bl_user.name) AS allowed_users

    FROM blr.bl_user
    LEFT JOIN blr.bl_link_user_to_enforcement_is_allowed ON
        blr.bl_link_user_to_enforcement_is_allowed.enforcement_id = $1.id

    WHERE blr.bl_link_user_to_enforcement_is_allowed.user_id = blr.bl_user.id

    GROUP BY $1.id;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION allowed_prs(blr.bl_enforcement) RETURNS text AS $$
    SELECT
        blr.commacat_all(DISTINCT cast(blr.bl_link_pr_to_enforcement_is_allowed.pr_number AS text)) AS allowed_prs

    FROM blr.bl_link_pr_to_enforcement_is_allowed
    WHERE blr.bl_link_pr_to_enforcement_is_allowed.enforcement_id = $1.id

    GROUP BY $1.id;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION users_who_can_edit(blr.bl_enforcement) RETURNS text AS $$
    SELECT
        blr.commacat_all(DISTINCT blr.bl_user.name) AS allowed_users

    FROM blr.bl_user
    LEFT JOIN blr.bl_link_user_to_enforcement_can_edit ON
        blr.bl_link_user_to_enforcement_can_edit.enforcement_id = $1.id

    WHERE blr.bl_link_user_to_enforcement_can_edit.user_id = blr.bl_user.id

    GROUP BY $1.id;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION users_who_can_enable(blr.bl_enforcement) RETURNS text AS $$
    SELECT
        blr.commacat_all(DISTINCT blr.bl_user.name) AS allowed_users

    FROM blr.bl_user
    LEFT JOIN blr.bl_link_user_to_enforcement_can_enable ON
        blr.bl_link_user_to_enforcement_can_enable.enforcement_id = $1.id

    WHERE blr.bl_link_user_to_enforcement_can_enable.user_id = blr.bl_user.id

    GROUP BY $1.id;
$$ LANGUAGE SQL;


-- Create Views
CREATE OR REPLACE VIEW blr.view_admins AS
    SELECT
        blr.bl_user.id    AS user_id,
        blr.bl_user.name  AS username,
        blr.bl_group.name AS group_name

    FROM blr.bl_user

    LEFT JOIN blr.bl_link_user_to_group ON
        blr.bl_link_user_to_group.user_id = blr.bl_user.id
    LEFT JOIN blr.bl_group ON
        blr.bl_group.id = blr.bl_link_user_to_group.group_id

    WHERE blr.bl_group.is_admin = TRUE;

CREATE OR REPLACE VIEW blr.view_locks AS
    SELECT
        blr.bl_lock.id,
        blr.bl_lock.name,
        blr.bl_lock.message,
        blr.bl_lock.status,
        blr.bl_lock.state,
        blr.bl_lock.grouped,
        blr.bl_lock.gate_keepers,
        blr.bl_lock.allowed_users,
        blr.bl_lock.allowed_prs,
        blr.bl_lock.old_lock,
        blr.bl_lock.old_release

    FROM blr.bl_lock;

CREATE OR REPLACE VIEW blr.view_lock_locations AS
    SELECT
        blr.bl_lock.id         AS lock_id,
        blr.bl_repository.name AS repository,
        blr.bl_path.name       AS path

    FROM blr.bl_lock

    LEFT JOIN blr.bl_link_location_to_lock ON
        blr.bl_link_location_to_lock.lock_id = blr.bl_lock.id
    LEFT JOIN blr.bl_location ON
        blr.bl_location.id = blr.bl_link_location_to_lock.location_id
    LEFT JOIN blr.bl_repository ON
        blr.bl_repository.id = blr.bl_location.repository_id
    LEFT JOIN blr.bl_path ON
        blr.bl_path.id = blr.bl_location.path_id;

CREATE OR REPLACE VIEW blr.view_lock_gate_keepers AS
    SELECT
        blr.bl_lock.id   AS lock_id,
        blr.bl_user.name AS gate_keeper

    FROM blr.bl_lock

    LEFT JOIN blr.bl_link_enforcement_to_lock ON
        blr.bl_link_enforcement_to_lock.lock_id = blr.bl_lock.id
    LEFT JOIN blr.bl_enforcement ON
        blr.bl_enforcement.id = blr.bl_link_enforcement_to_lock.enforcement_id
    LEFT JOIN blr.bl_link_user_to_enforcement_can_edit ON
        blr.bl_link_user_to_enforcement_can_edit.enforcement_id = blr.bl_enforcement.id
    LEFT JOIN blr.bl_user ON
        blr.bl_user.id = blr.bl_link_user_to_enforcement_can_edit.user_id;

CREATE OR REPLACE VIEW blr.view_lock_enforcements AS
    SELECT
        blr.bl_lock.id          AS lock_id,
        blr.bl_enforcement.id   AS enforcement_id,
        blr.bl_enforcement.name AS enforcement_name

    FROM blr.bl_lock

    LEFT JOIN blr.bl_link_enforcement_to_lock ON
        blr.bl_link_enforcement_to_lock.lock_id = blr.bl_lock.id
    LEFT JOIN blr.bl_enforcement ON
        blr.bl_enforcement.id = blr.bl_link_enforcement_to_lock.enforcement_id

    WHERE blr.bl_enforcement.name IS NOT NULL;

CREATE OR REPLACE VIEW blr.view_enforcements AS
    SELECT
        blr.bl_enforcement.id,
        blr.bl_enforcement.name,
        blr.bl_enforcement.is_enabled,
        blr.bl_enforcement.users_who_can_edit,
        blr.bl_enforcement.users_who_can_enable,
        blr.bl_enforcement.allowed_users,
        blr.bl_enforcement.allowed_prs

    FROM blr.bl_enforcement;

CREATE OR REPLACE VIEW blr.view_audit_trail AS
    SELECT
        blr.bl_audit_transaction.id                     AS audit_transaction_id,
        blr.bl_audit_event.id                           AS audit_event_id,
        blr.bl_user.name                                AS username,
        on_behalf.name                                  AS on_behalf_of,
        blr.bl_audit_event.table_name                   AS table_name,
        blr.bl_audit_transaction.start_timestamp        AS start_timestamp,
        blr.bl_audit_transaction.end_timestamp          AS end_timestamp,
        blr.bl_audit_event.action                       AS action,
        blr.bl_audit_event.old_data                     AS old_data,
        blr.bl_audit_event.new_data                     AS new_data

    FROM blr.bl_audit_event
    LEFT JOIN blr.bl_audit_transaction ON blr.bl_audit_event.audit_transaction_id = blr.bl_audit_transaction.id
    LEFT JOIN blr.bl_api_key ON blr.bl_audit_transaction.api_key_id = blr.bl_api_key.id
    LEFT JOIN blr.bl_user ON blr.bl_api_key.user_id = blr.bl_user.id
    LEFT JOIN blr.bl_user AS on_behalf ON blr.bl_audit_transaction.as_user_id = on_behalf.id;

-- Create Triggers
CREATE TRIGGER bl_user_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_user
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_group_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_group
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_repository_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_repository
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_path_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_path
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_location_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_location
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_lock_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_lock
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_enforcement_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_enforcement
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_link_user_to_group_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_link_user_to_group
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_link_location_to_lock_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_link_location_to_lock
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_link_enforcement_to_lock_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_link_enforcement_to_lock
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_link_user_to_enforcement_can_enable_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_link_user_to_enforcement_can_enable
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_link_user_to_enforcement_can_edit_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_link_user_to_enforcement_can_edit
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_link_user_to_enforcement_is_allowed_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_link_user_to_enforcement_is_allowed
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_link_pr_to_enforcement_is_allowed_audit
    AFTER INSERT OR UPDATE OR DELETE ON blr.bl_link_pr_to_enforcement_is_allowed
    FOR EACH ROW EXECUTE PROCEDURE blr.if_modified_func();

CREATE TRIGGER bl_audit_transaction_connection
    AFTER INSERT ON blr.bl_audit_transaction
    FOR EACH ROW EXECUTE PROCEDURE blr.at_started_func();

-- REVOKE SCHEMA Privileges
REVOKE ALL PRIVILEGES ON SCHEMA blr FROM PUBLIC CASCADE;

-- GRANT SCHEMA Privileges
GRANT USAGE ON SCHEMA blr    TO PUBLIC;
GRANT USAGE ON SCHEMA public TO PUBLIC;

-- GRANT TABLE Privileges
GRANT SELECT ON TABLE blr.bl_user                                  TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_group                                 TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_repository                            TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_path                                  TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_location                              TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_lock                                  TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_enforcement                           TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_audit_event                           TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_audit_transaction                     TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_link_user_to_group                    TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_link_location_to_lock                 TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_link_enforcement_to_lock              TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_link_user_to_enforcement_can_enable   TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_link_user_to_enforcement_can_edit     TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_link_user_to_enforcement_is_allowed   TO PUBLIC;
GRANT SELECT ON TABLE blr.bl_link_pr_to_enforcement_is_allowed     TO PUBLIC;
GRANT SELECT ON TABLE blr.view_admins                              TO PUBLIC;
GRANT SELECT ON TABLE blr.view_locks                               TO PUBLIC;
GRANT SELECT ON TABLE blr.view_lock_enforcements                   TO PUBLIC;
GRANT SELECT ON TABLE blr.view_lock_locations                      TO PUBLIC;
GRANT SELECT ON TABLE blr.view_lock_gate_keepers                   TO PUBLIC;

-- Set TABLE Ownership
ALTER TABLE blr.bl_user                                  OWNER TO blr_w;
ALTER TABLE blr.bl_group                                 OWNER TO blr_w;
ALTER TABLE blr.bl_repository                            OWNER TO blr_w;
ALTER TABLE blr.bl_path                                  OWNER TO blr_w;
ALTER TABLE blr.bl_location                              OWNER TO blr_w;
ALTER TABLE blr.bl_lock                                  OWNER TO blr_w;
ALTER TABLE blr.bl_enforcement                           OWNER TO blr_w;
ALTER TABLE blr.bl_audit_event                           OWNER TO blr_w;
ALTER TABLE blr.bl_audit_transaction                     OWNER TO blr_w;
ALTER TABLE blr.bl_api_key                               OWNER TO blr_w;
ALTER TABLE blr.bl_link_user_to_group                    OWNER TO blr_w;
ALTER TABLE blr.bl_link_location_to_lock                 OWNER TO blr_w;
ALTER TABLE blr.bl_link_enforcement_to_lock              OWNER TO blr_w;
ALTER TABLE blr.bl_link_user_to_enforcement_can_enable   OWNER TO blr_w;
ALTER TABLE blr.bl_link_user_to_enforcement_can_edit     OWNER TO blr_w;
ALTER TABLE blr.bl_link_user_to_enforcement_is_allowed   OWNER TO blr_w;
ALTER TABLE blr.bl_link_pr_to_enforcement_is_allowed     OWNER TO blr_w;
ALTER TABLE blr.view_admins                              OWNER TO blr_w;
ALTER TABLE blr.view_locks                               OWNER TO blr_w;
ALTER TABLE blr.view_lock_enforcements                   OWNER TO blr_w;
ALTER TABLE blr.view_lock_locations                      OWNER TO blr_w;
ALTER TABLE blr.view_lock_gate_keepers                   OWNER TO blr_w;
ALTER TABLE blr.view_enforcements                        OWNER TO blr_w;
ALTER TABLE blr.view_audit_trail                         OWNER TO blr_w;

-- Needed Default Values
INSERT INTO blr.bl_user (name) VALUES ('admin');
INSERT INTO blr.bl_api_key (api_key, user_id, can_impersonate)
    VALUES ('Super Secret Admin API Key', 1, TRUE);
INSERT INTO blr.bl_group (name, is_admin) VALUES ('Admin', TRUE);
INSERT INTO blr.bl_link_user_to_group (user_id, group_id) VALUES (1,1);

INSERT INTO blr.bl_user (name) VALUES ('Branch Locker GUI');
INSERT INTO blr.bl_api_key (api_key, user_id, can_impersonate)
    VALUES ('Super Secret GUI API Key', 2, TRUE);
