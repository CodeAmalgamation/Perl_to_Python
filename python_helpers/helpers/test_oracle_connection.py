#!/usr/bin/env python3
"""
Test Oracle connection directly to debug issues
"""

import sys

def test_oracle_drivers():
    """Test which Oracle drivers are available"""
    print("Testing Oracle drivers...")
    
    # Test oracledb
    try:
        import oracledb
        print("✓ oracledb is available")
        print(f"  Version: {getattr(oracledb, '__version__', 'unknown')}")
        return 'oracledb'
    except ImportError as e:
        print(f"✗ oracledb not available: {e}")
    
    # Test cx_Oracle
    try:
        import cx_Oracle
        print("✓ cx_Oracle is available")
        print(f"  Version: {getattr(cx_Oracle, 'version', 'unknown')}")
        return 'cx_Oracle'
    except ImportError as e:
        print(f"✗ cx_Oracle not available: {e}")
    
    return None

def test_oracle_connection():
    """Test Oracle connection with your specific parameters"""
    
    # Your connection details - both formats
    dsn_dbi = "dbi:Oracle:host=X092B-SCAN;port=2210;service_name=P_PDEQ_APP.SALEM.PAYMENTECH.COM"
    dsn_direct = "X092B-SCAN:2210/P_PDEQ_APP.SALEM.PAYMENTECH.COM"
    username = "APP_30166_PDE_APP"
    password = "your_password_here"  # Replace with actual password
    
    print(f"\nTesting connection with both formats:")
    print(f"DBI format: {dsn_dbi}")
    print(f"Direct format: {dsn_direct}")
    print(f"Username: {username}")
    
    # Test both DSN formats
    for dsn_name, dsn in [("DBI", dsn_dbi), ("Direct", dsn_direct)]:
        print(f"\n{'='*50}")
        print(f"Testing {dsn_name} format: {dsn}")
        
        # Parse DSN
        params = {}
        if dsn.startswith('dbi:'):
            parts = dsn.split(':', 2)
            if len(parts) >= 3:
                db_info = parts[2]
                for param in db_info.split(';'):
                    if '=' in param:
                        key, value = param.split('=', 1)
                        params[key.lower().strip()] = value.strip()
        else:
            # Direct format: X092B-SCAN:2210/P_PDEQ_APP.SALEM.PAYMENTECH.COM
            if ':' in dsn and '/' in dsn:
                host_port, service = dsn.split('/', 1)
                if ':' in host_port:
                    host, port = host_port.split(':', 1)
                    params['host'] = host.strip()
                    params['port'] = port.strip()
                    params['service_name'] = service.strip()
        
        print(f"\nParsed parameters:")
        for key, value in params.items():
            print(f"  {key}: {value}")
        
        # Validate parameters
        if not params.get('service_name'):
            print("ERROR: No service_name found in DSN")
            continue
            
        service_name = params['service_name']
        print(f"\nService name: {service_name}")
        print("This looks like a valid Oracle service name with domain components")
        
        # Test connection
        driver = test_oracle_drivers()
        if not driver:
            print("\nNo Oracle drivers available. Install with:")
            print("  pip install oracledb")
            return
        
        try:
            if driver == 'oracledb':
                import oracledb
                
                host = params.get('host', 'localhost')
                port = params.get('port', '1521')
                service = params['service_name']
                
                connect_string = f"{host}:{port}/{service}"
                print(f"\nAttempting oracledb connection: {connect_string}")
                
                conn = oracledb.connect(
                    user=username,
                    password=password,
                    dsn=connect_string
                )
                
                print("✓ Connection successful!")
                
                # Test a simple query
                cursor = conn.cursor()
                cursor.execute("SELECT SYSDATE as current_date, USER as current_user FROM DUAL")
                row = cursor.fetchone()
                print(f"Query result: {row}")
                
                cursor.close()
                conn.close()
                break  # Success - no need to test other format
                
            elif driver == 'cx_Oracle':
                import cx_Oracle
                
                host = params.get('host', 'localhost')
                port = int(params.get('port', '1521'))
                service = params['service_name']
                
                dsn_string = cx_Oracle.makedsn(host, port, service_name=service)
                print(f"\nAttempting cx_Oracle connection: {dsn_string}")
                
                conn = cx_Oracle.connect(username, password, dsn_string)
                
                print("✓ Connection successful!")
                
                # Test a simple query
                cursor = conn.cursor()
                cursor.execute("SELECT SYSDATE as current_date, USER as current_user FROM DUAL")
                row = cursor.fetchone()
                print(f"Query result: {row}")
                
                cursor.close()
                conn.close()
                break  # Success - no need to test other format
                
        except Exception as e:
            print(f"✗ Connection failed: {e}")
            print(f"Error type: {type(e).__name__}")
            
            # Common error suggestions
            print("\nCommon issues and solutions:")
            print("1. Check if Oracle client libraries are installed")
            print("2. Verify the hostname and port are correct")
            print("3. Check network connectivity and firewall settings") 
            print("4. Verify username and password")
            print("5. Confirm the service name is accessible")
            print(f"6. Try: telnet {params.get('host', 'unknown')} {params.get('port', 'unknown')}")
    
    print(f"\n{'='*50}")
    print("Connection test completed")
                
if __name__ == "__main__":
    test_oracle_connection()