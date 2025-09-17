#!/usr/bin/env python3
"""
Direct test for database.py Oracle-only connectivity using oracledb driver
Usage: python test_oracle_direct.py
"""

import sys
import os

# Add the helpers directory to Python path
script_dir = os.path.dirname(os.path.abspath(__file__))
helpers_dir = os.path.join(script_dir, 'python_helpers', 'helpers')
sys.path.insert(0, helpers_dir)

import database

def test_oracle_connection():
    """Test Oracle database connection"""

    # Replace these with your actual Oracle credentials
    dsn = input("Enter Oracle DSN (e.g., 'dbi:Oracle:localhost:1521:XE' or TNS name): ").strip()
    username = input("Enter username: ").strip()
    password = input("Enter password: ").strip()

    print(f"\n🔗 Testing Oracle connection...")
    print(f"DSN: {dsn}")
    print(f"Username: {username}")
    print(f"Password: {'*' * len(password)}")

    # Test connection
    result = database.connect(dsn, username, password)

    if result['success']:
        connection_id = result['connection_id']
        db_type = result['db_type']

        print(f"✅ Connection successful!")
        print(f"Connection ID: {connection_id}")
        print(f"Database type: {db_type}")

        # Test a simple query
        print(f"\n📋 Testing query execution...")

        # Prepare simple Oracle query
        prepare_result = database.prepare(connection_id, "SELECT SYSDATE FROM DUAL")

        if prepare_result['success']:
            statement_id = prepare_result['statement_id']
            print(f"✅ Statement prepared: {statement_id}")

            # Execute query
            exec_result = database.execute_statement(connection_id, statement_id)

            if exec_result['success']:
                print(f"✅ Query executed successfully")
                print(f"Columns: {exec_result.get('column_info', {}).get('names', [])}")

                # Fetch result
                fetch_result = database.fetch_row(connection_id, statement_id, format='hash')

                if fetch_result['success']:
                    print(f"✅ Data fetched: {fetch_result['row']}")
                else:
                    print(f"❌ Fetch failed: {fetch_result.get('error', 'Unknown error')}")

                # Clean up statement
                database.finish_statement(connection_id, statement_id)
            else:
                print(f"❌ Execute failed: {exec_result.get('error', 'Unknown error')}")
        else:
            print(f"❌ Prepare failed: {prepare_result.get('error', 'Unknown error')}")

        # Test immediate execution
        print(f"\n⚡ Testing immediate execution...")
        immediate_result = database.execute_immediate(connection_id, "SELECT USER FROM DUAL")

        if immediate_result['success']:
            print(f"✅ Immediate execution successful")
            print(f"Rows affected: {immediate_result['rows_affected']}")
        else:
            print(f"❌ Immediate execution failed: {immediate_result.get('error', 'Unknown error')}")

        # Close connection
        print(f"\n🔌 Closing connection...")
        disconnect_result = database.disconnect(connection_id)

        if disconnect_result['success']:
            print(f"✅ Connection closed successfully")
        else:
            print(f"❌ Disconnect failed: {disconnect_result.get('error', 'Unknown error')}")

    else:
        print(f"❌ Connection failed: {result.get('error', 'Unknown error')}")
        if 'traceback' in result:
            print(f"Traceback: {result['traceback']}")

def test_dsn_parsing():
    """Test DSN parsing functionality"""

    print("\n🔍 Testing DSN parsing...")

    test_dsns = [
        "dbi:Oracle:localhost:1521:XE",
        "dbi:Oracle:host=localhost;port=1521;service_name=ORCL",
        "dbi:Oracle:PROD_TNS",
        "localhost:1521/ORCL"
    ]

    for dsn in test_dsns:
        print(f"\nParsing DSN: {dsn}")
        try:
            from database import _parse_oracle_dsn

            # Test Oracle DSN parsing
            oracle_params = _parse_oracle_dsn(dsn)
            print(f"  Oracle params: {oracle_params}")

        except Exception as e:
            print(f"  ❌ Error: {e}")

def check_oracle_drivers():
    """Check oracledb driver availability"""

    print("\n🔍 Checking Oracle driver...")

    try:
        import oracledb
        print(f"  ✅ oracledb: {oracledb.__version__}")
        return True
    except ImportError:
        print("  ❌ oracledb: Not available")
        print("\n⚠️  oracledb driver not found. Install with:")
        print("    pip install oracledb")
        return False

if __name__ == "__main__":
    print("🔗 Oracle Database Direct Test")
    print("=" * 40)

    # Check drivers first
    if not check_oracle_drivers():
        print("\n❌ Cannot proceed without oracledb driver")
        sys.exit(1)

    # Test DSN parsing
    test_dsn_parsing()

    # Test actual connection
    try:
        test_oracle_connection()
    except KeyboardInterrupt:
        print("\n\n👋 Test cancelled by user")
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()