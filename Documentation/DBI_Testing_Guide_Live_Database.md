# DBI Testing Guide - Live Database with Kerberos

**Addendum to**: DBI_Testing_Guide.md
**Date**: October 6, 2025
**Version**: 1.0
**Branch**: feature/dbi
**Audience**: QA Testers testing against real Oracle database

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites for Live Testing](#prerequisites-for-live-testing)
3. [Kerberos Setup](#kerberos-setup)
4. [Database Configuration](#database-configuration)
5. [Running Live Tests](#running-live-tests)
6. [Troubleshooting Live Database Issues](#troubleshooting-live-database-issues)
7. [Expected Differences from Simulated Tests](#expected-differences-from-simulated-tests)

---

## Overview

### What's Different?

When testing with a **live Oracle database**, you get:
- ✅ **Real data** - Actual database queries and results
- ✅ **More comprehensive testing** - Tests actual Oracle behavior
- ✅ **Performance metrics** - See actual connection times
- ✅ **Kerberos authentication** - Tests real security setup

**The original testing guide** (DBI_Testing_Guide.md) tests the **logic** without a database.
**This guide** tests everything **end-to-end** with a real Oracle database.

---

## Prerequisites for Live Testing

### 1. Oracle Database Access

You need:
- [ ] **Database server address** (hostname or IP)
- [ ] **Database name/SID** (e.g., PRODDB, TESTDB)
- [ ] **Network access** to the database server (no firewall blocking)

**How to check**: Ask your DBA or check your tnsnames.ora file

---

### 2. Kerberos Setup

**What is Kerberos?**
Think of Kerberos like a secure ID badge system:
- Instead of showing your password every time
- You get a "ticket" that proves who you are
- The ticket expires after a few hours (like a day pass)

**You need**:
- [ ] Kerberos configured on your machine
- [ ] Valid Kerberos ticket (we'll show you how to get one)
- [ ] Oracle client configured for Kerberos

**How to check**: Run `which kinit` - if it shows a path, you have Kerberos

---

### 3. Oracle Client

**What is it?**
Software that lets Python talk to Oracle databases.

**You need**:
- [ ] Oracle Instant Client OR Oracle Full Client installed
- [ ] Python oracledb package installed

**How to check**:
```bash
python3 -c "import oracledb; print(oracledb.version)"
```

**Expected output**: Something like `2.0.0` or similar

**If you get an error**:
```bash
pip3 install oracledb
```

---

## Kerberos Setup

### Step 1: Get Your Kerberos Ticket

**What this does**: Gets you a security "pass" to access the database

**Command**:
```bash
kinit your_username@YOUR.DOMAIN
```

**Example**:
```bash
kinit jdoe@COMPANY.COM
```

**What happens**:
1. It will ask for your password
2. Type your network password (you won't see anything as you type - this is normal!)
3. Press Enter
4. If successful, you'll see no output (no news is good news!)

**Common format variations**:
- `kinit jdoe@COMPANY.COM` - Most common
- `kinit jdoe` - If domain is configured by default
- `kinit john.doe@COMPANY.COM` - If you use full name

**Ask your IT/DBA team** if you're not sure about the format!

---

### Step 2: Verify Your Ticket

**Command**:
```bash
klist
```

**Good output** (ticket is valid):
```
Ticket cache: FILE:/tmp/krb5cc_1000
Default principal: jdoe@COMPANY.COM

Valid starting     Expires            Service principal
10/06/25 09:00:00  10/06/25 19:00:00  krbtgt/COMPANY.COM@COMPANY.COM
```

**What to look for**:
- ✅ You see your username
- ✅ "Valid starting" shows today's date
- ✅ "Expires" is in the future (usually 10 hours from now)

**Bad output** (no ticket or expired):
```
klist: No credentials cache found
```

**Fix**: Run `kinit` again

---

### Step 3: Understanding Ticket Expiration

**Important**: Kerberos tickets **expire**!

- **Typical lifespan**: 10 hours
- **What happens when expired**: Database connections will fail
- **How to check**: Run `klist` - look at the "Expires" time
- **How to renew**: Run `kinit` again

**Pro tip**: If you get weird database errors, first check if your ticket expired!

---

## Database Configuration

### Step 1: Create Configuration File

**What this does**: Stores your database connection details safely

**Command**:
```bash
cd /Users/shubhamdixit/Perl_to_Python/Test_Scripts
cp db_config.pl.template db_config.pl
```

**What happened**: Created a copy of the template that you can edit

---

### Step 2: Edit Configuration File

**Open the file**:
```bash
nano db_config.pl
```
*(or use your favorite editor: vim, emacs, TextEdit)*

**What to change**:

#### For Kerberos Authentication (Most Common)

Find these lines and edit them:

```perl
# BEFORE (template values):
our $DSN = 'dbi:Oracle:YOURDB';  # ← CHANGE THIS
our $AUTH_METHOD = 'kerberos';   # ← Leave as 'kerberos'
our $USERNAME = '';              # ← Leave empty for Kerberos
our $PASSWORD = '';              # ← Leave empty for Kerberos
```

```perl
# AFTER (your actual values):
our $DSN = 'dbi:Oracle:PRODDB';  # ← Your database name
our $AUTH_METHOD = 'kerberos';   # ← Keep as 'kerberos'
our $USERNAME = '';              # ← Leave empty
our $PASSWORD = '';              # ← Leave empty
```

**How to find your DSN**:
1. Ask your DBA
2. OR check your tnsnames.ora file (usually in $ORACLE_HOME/network/admin/)
3. OR use the format: `dbi:Oracle:host=dbserver.company.com;port=1521;sid=PRODDB`

**Examples of DSN**:
```perl
# Simple (just database name):
our $DSN = 'dbi:Oracle:PRODDB';

# TNS name (from tnsnames.ora):
our $DSN = 'dbi:Oracle:MY_TNS_ALIAS';

# Full connection string:
our $DSN = 'dbi:Oracle:host=prod-db01.company.com;port=1521;service_name=PRODDB';
```

---

#### For Password Authentication (Less Common)

**If you're NOT using Kerberos**, change to:

```perl
our $DSN = 'dbi:Oracle:TESTDB';
our $AUTH_METHOD = 'password';   # ← Changed to 'password'
our $USERNAME = 'your_db_username';  # ← Your database username
our $PASSWORD = 'your_db_password';  # ← Your database password
```

**⚠️ Security Warning**: If using passwords:
- Never commit db_config.pl to git (it's already in .gitignore)
- Don't share your password
- Use a dedicated test account, not your personal account

---

### Step 3: Save and Close

**In nano**:
- Press `Ctrl + X`
- Press `Y` (to confirm save)
- Press `Enter`

**Verify it saved**:
```bash
cat db_config.pl | grep "our \$DSN"
```

You should see your database name, not "YOURDB"

---

## Running Live Tests

### Option 1: Quick Live Test (Recommended First)

**What it does**: Single comprehensive test that exercises all features

**Command**:
```bash
cd /Users/shubhamdixit/Perl_to_Python
chmod +x Test_Scripts/test_live_database.pl
perl Test_Scripts/test_live_database.pl
```

**Expected output** (if everything works):
```
=== Live Database Test ===

✅ Loaded database configuration from db_config.pl
   DSN: dbi:Oracle:PRODDB
   Auth Method: kerberos

Checking Kerberos ticket status...
✅ Kerberos ticket found and valid
   Ticket info:
   ...

Test 1: Connecting to Oracle database...
✅ Successfully connected to Oracle database
   Connection ID: conn_abc123
✅ Test 1: Database connection successful - PASSED

Test 2: Executing simple query...
✅ Query executed successfully
   Message: Hello from Oracle
   Date: 06-OCT-25
   User: JDOE
✅ Test 2: Simple query execution - PASSED

...

============================================================
LIVE DATABASE TEST SUMMARY
============================================================
Database: dbi:Oracle:PRODDB
Auth Method: kerberos
Total tests: 8
Passed: 8
Failed: 0
Success rate: 100.0%

🎉 ALL TESTS PASSED!

✅ Database connection working
✅ Phase 1 features verified on live database
✅ Phase 2 features verified on live database
✅ Ready for production use
```

**How long it takes**: About 30-60 seconds

---

### Option 2: Run Individual Tests with Live Database

You can also run the original test scripts - they'll detect the `db_config.pl` file and use it automatically:

```bash
# These will now connect to real database if db_config.pl exists:
perl Test_Scripts/test_connect_cached.pl
perl Test_Scripts/test_do_statement.pl
perl Test_Scripts/test_phase1_complete.pl
perl Test_Scripts/test_column_metadata.pl
```

**Note**: Some tests are designed for simulated mode and might skip certain checks with a live database.

---

## Troubleshooting Live Database Issues

### Issue 1: "No valid Kerberos ticket found"

**Error message**:
```
❌ No valid Kerberos ticket found
   Please run: kinit your_username@YOUR.DOMAIN
```

**What went wrong**: Your Kerberos ticket expired or doesn't exist

**How to fix**:
```bash
kinit your_username@YOUR.DOMAIN
```

Then run the test again.

**Prevention**: Check ticket before testing:
```bash
klist
```

---

### Issue 2: "Connection refused" or "ORA-12154"

**Error message**:
```
❌ Failed to connect to database
   Error: ORA-12154: TNS:could not resolve the connect identifier
```

**What went wrong**: Database name (DSN) is incorrect or not found

**How to fix**:
1. **Check your DSN** in `db_config.pl`
2. **Verify database is accessible**:
   ```bash
   tnsping PRODDB
   ```
3. **Try full connection string** instead of TNS name:
   ```perl
   our $DSN = 'dbi:Oracle:host=dbserver.company.com;port=1521;sid=PRODDB';
   ```

4. **Ask your DBA** for the correct connection details

---

### Issue 3: "ORA-01017: invalid username/password"

**Error message**:
```
❌ Failed to connect to database
   Error: ORA-01017: invalid username/password; logon denied
```

**What went wrong**:
- For Kerberos: Ticket is invalid or Kerberos not configured correctly
- For password: Wrong username or password

**How to fix**:

**If using Kerberos**:
```bash
# Get fresh ticket:
kdestroy    # Destroy old ticket
kinit your_username@YOUR.DOMAIN   # Get new ticket
klist       # Verify it's valid
```

**If using password**:
- Double-check username and password in `db_config.pl`
- Ask DBA to verify your account is active
- Try logging in with SQL*Plus to verify credentials:
  ```bash
  sqlplus username@PRODDB
  ```

---

### Issue 4: "DPY-6000: cannot connect to database"

**Error message**:
```
❌ Failed to connect to database
   Error: DPY-6000: cannot connect to database. Listener refused connection.
```

**What went wrong**:
- Database server is down
- Network is blocking connection
- Wrong port number

**How to fix**:
1. **Check if database is up** (ask DBA)
2. **Check network connectivity**:
   ```bash
   ping dbserver.company.com
   telnet dbserver.company.com 1521
   ```
3. **Verify firewall rules** (ask network team)
4. **Check from another machine** on same network

---

### Issue 5: "Oracle client library not found"

**Error message**:
```
DPY-6001: cannot connect to database. Oracle Client library cannot be loaded
```

**What went wrong**: Oracle Instant Client not installed or not in PATH

**How to fix**:

**On Linux/Mac**:
```bash
# Download Oracle Instant Client from oracle.com
# Extract to /opt/oracle/instantclient_21_1 (or similar)

# Set environment variables:
export ORACLE_HOME=/opt/oracle/instantclient_21_1
export LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_PATH
export PATH=$ORACLE_HOME:$PATH

# Verify:
ls $ORACLE_HOME/libclntsh.so*
```

**Ask your system administrator** for help installing Oracle Client.

---

### Issue 6: Test shows "⚠️ Warnings" but passes

**Example output**:
```
⚠️  No Oracle DB available (expected)
Testing with simulated data...
✅ Test 1: Feature logic correct - PASSED
```

**What it means**: Test is running in "simulation mode" even though you have db_config.pl

**What went wrong**: The test script doesn't support live database mode

**Is this bad?**: NO - the test still validates the logic works correctly

**How to get full live testing**: Use `test_live_database.pl` instead

---

## Expected Differences from Simulated Tests

### What Changes with Live Database?

| Aspect | Simulated Mode | Live Database Mode |
|--------|----------------|-------------------|
| **Connection** | Always fails (expected) | Actually connects to Oracle |
| **Queries** | Return fake data | Return real data from database |
| **Performance** | Instant | Realistic (network latency) |
| **Errors** | Simulated errors | Real Oracle errors |
| **Data validation** | Logic only | Full end-to-end validation |

---

### Simulated Mode Output:

```
⚠️  No Oracle DB available (expected)
   Testing with simulated data...
✅ Test 1: Connection logic correct - PASSED
```

**Meaning**: Tests the code logic is correct, but doesn't connect to real database

---

### Live Database Mode Output:

```
✅ Loaded database configuration from db_config.pl
✅ Kerberos ticket found and valid
✅ Successfully connected to Oracle database
   Connection ID: conn_abc123
✅ Test 1: Database connection successful - PASSED
```

**Meaning**: Actually connected to Oracle and ran real queries

---

## Quick Reference: Live Database Testing Checklist

### Before You Start
- [ ] Kerberos ticket is valid (`klist`)
- [ ] Oracle client is installed (`python3 -c "import oracledb"`)
- [ ] `db_config.pl` file created and configured
- [ ] Network access to database server
- [ ] Python daemon is running

### Get Kerberos Ticket
```bash
kinit your_username@YOUR.DOMAIN
klist  # Verify it worked
```

### Run Live Database Test
```bash
cd /Users/shubhamdixit/Perl_to_Python
perl Test_Scripts/test_live_database.pl
```

### If Tests Fail
1. [ ] Check Kerberos ticket: `klist`
2. [ ] Verify DSN in `db_config.pl`
3. [ ] Test database connectivity: `tnsping YOURDB`
4. [ ] Check Python daemon is running
5. [ ] Review error message and check troubleshooting section

### After Testing
- [ ] All 8 tests passed? ✅ Report "Live database tests PASS"
- [ ] Some tests failed? ❌ Report failures with full output
- [ ] Cannot connect? 📋 Provide error message and troubleshooting steps tried

---

## What to Report

### If All Tests Pass ✅

```
Live Database Testing Complete - ALL PASS ✅

Date: [Today's date]
Branch: feature/dbi
Database: [Your DSN]
Auth Method: Kerberos
Total tests run: 8
Results: 8/8 PASSED (100%)

All features verified against live Oracle database:
✅ Kerberos authentication working
✅ Database connectivity working
✅ All Phase 1 features working
✅ All Phase 2 features working

System is production-ready for Oracle connections.
```

---

### If Connection Fails ❌

```
Live Database Testing - CONNECTION FAILED ❌

Date: [Today's date]
Branch: feature/dbi

Connection Details:
DSN: [Your DSN]
Auth Method: Kerberos
Kerberos ticket: [Valid/Invalid - from klist output]

Error:
[Paste full error message]

Troubleshooting steps tried:
- [ ] Verified Kerberos ticket with klist
- [ ] Tested DSN with tnsping
- [ ] Checked Oracle client installation
- [ ] [Other steps you tried]

Need DBA/Network assistance to proceed.
```

---

### If Some Tests Pass, Some Fail ⚠️

```
Live Database Testing - PARTIAL SUCCESS ⚠️

Date: [Today's date]
Branch: feature/dbi
Database: [Your DSN]
Auth Method: Kerberos

Results: 5/8 tests passed (62.5%)

Passed tests:
✅ Test 1: Database connection
✅ Test 2: Simple query
✅ Test 3: Column metadata
✅ Test 4: NULL handling
✅ Test 5: Prepare/execute

Failed tests:
❌ Test 6: Connection caching
❌ Test 7: Session initialization
❌ Test 8: Error handling

[Paste error output for failed tests]

Need developer review of failures.
```

---

## Security Reminders

### ✅ DO:
- Use Kerberos authentication when possible
- Keep `db_config.pl` file private (it's in .gitignore)
- Renew Kerberos tickets before they expire
- Use dedicated test accounts, not production accounts
- Log out of Kerberos when done: `kdestroy`

### ❌ DON'T:
- Commit `db_config.pl` to git
- Share your Kerberos password
- Use production database for destructive tests
- Leave Kerberos tickets active overnight on shared machines
- Hard-code passwords in test scripts

---

## Getting Help

### Questions to Ask Your Team

**For Database Connection Issues**:
- "What is the correct DSN/TNS name for the test database?"
- "What Oracle client version should I use?"
- "Is the database accessible from my machine?"

**For Kerberos Issues**:
- "What is the correct Kerberos realm (e.g., COMPANY.COM)?"
- "What format should I use for kinit (username or username@REALM)?"
- "Is Kerberos configured on this machine?"

**For Test Failures**:
- "Can you review the test output? I'm not sure if this is expected."
- "Test X is failing with error Y - is this a known issue?"

---

## Advanced: Running Tests in Different Environments

### Testing Against Multiple Databases

Create multiple config files:

```bash
# For DEV database:
cp db_config.pl.template db_config_dev.pl
# Edit with DEV database details

# For TEST database:
cp db_config.pl.template db_config_test.pl
# Edit with TEST database details
```

**Then run with specific config**:
```bash
# TODO: This would require modifying test scripts to accept config file parameter
# For now, manually rename the config file you want to use to db_config.pl
```

---

**Document End**

*This guide supplements the main DBI_Testing_Guide.md with live database testing procedures. For general information about what was changed and why, refer to the main guide.*
