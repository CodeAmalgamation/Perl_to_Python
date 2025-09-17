#!/usr/bin/env python3
"""
email_helper.py - Email helper module for CPAN bridge
Provides Mail::Sender functionality using Python's email libraries
Renamed from email.py to avoid conflict with Python's email module
"""

import smtplib
import os
import sys
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from email import encoders
from email.utils import formatdate, make_msgid
from pathlib import Path
import mimetypes

def send_multipart(**kwargs):
    """
    Send multipart email with optional attachments
    Matches Mail::Sender's OpenMultipart/Attach/Close pattern
    """
    smtp_host = kwargs.get('smtp_host', 'localhost')
    smtp_port = kwargs.get('smtp_port', 25)
    from_addr = kwargs['from']
    to_addr = kwargs['to']
    subject = kwargs.get('subject', '')
    body = kwargs.get('body', '')
    body_encoding = kwargs.get('body_encoding', 'quoted-printable')
    attachments = kwargs.get('attachments', [])
    headers = kwargs.get('headers', {})
    multipart_type = kwargs.get('multipart_type', 'mixed')
    
    # Handle multiple recipients
    if isinstance(to_addr, list):
        to_list = to_addr
        to_addr = ', '.join(to_addr)
    else:
        to_list = [addr.strip() for addr in to_addr.split(',')]
    
    # Create message
    msg = MIMEMultipart(multipart_type)
    msg['From'] = from_addr
    msg['To'] = to_addr
    msg['Subject'] = subject
    msg['Date'] = formatdate(localtime=True)
    msg['Message-ID'] = make_msgid()
    
    # Add custom headers
    for key, value in headers.items():
        if key.lower() not in ['from', 'to', 'subject', 'date', 'message-id']:
            msg[key] = value
    
    # Add body if present
    if body:
        text_part = MIMEText(body, 'plain')
        if body_encoding.lower() == 'quoted-printable':
            text_part.set_charset('utf-8')
        msg.attach(text_part)
    
    # Add attachments
    for attachment in attachments:
        attach_file(msg, attachment)
    
    # Send email
    try:
        with smtplib.SMTP(smtp_host, smtp_port) as server:
            # No authentication for localhost
            server.send_message(msg, from_addr, to_list)
        return {"status": "sent", "message": "Email sent successfully"}
    except Exception as e:
        raise RuntimeError(f"Failed to send email: {str(e)}")

def attach_file(msg, attachment_info):
    """
    Attach a file to the message
    """
    file_path = attachment_info['file']
    
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Attachment file not found: {file_path}")
    
    # Determine MIME type
    ctype = attachment_info.get('ctype', 'application/octet-stream')
    encoding = attachment_info.get('encoding', 'base64')
    disposition = attachment_info.get('disposition', f'attachment; filename={os.path.basename(file_path)}')
    description = attachment_info.get('description', f'Attached file {os.path.basename(file_path)}')
    
    # Read file
    with open(file_path, 'rb') as f:
        file_data = f.read()
    
    # Create appropriate MIME part
    maintype, subtype = ctype.split('/', 1) if '/' in ctype else (ctype, 'octet-stream')
    
    if maintype == 'text':
        # Text files
        try:
            # Try to decode as text
            text_data = file_data.decode('utf-8')
            part = MIMEText(text_data, subtype)
        except UnicodeDecodeError:
            # Fall back to binary
            part = MIMEBase(maintype, subtype)
            part.set_payload(file_data)
            encoders.encode_base64(part)
    else:
        # Binary files
        part = MIMEBase(maintype, subtype)
        part.set_payload(file_data)
        
        # Apply encoding
        if encoding.lower() == 'base64':
            encoders.encode_base64(part)
        elif encoding.lower() == 'quoted-printable':
            encoders.encode_quopri(part)
        elif encoding.lower() in ['7bit', '8bit']:
            # No encoding needed
            pass
        else:
            # Default to base64 for unknown encodings
            encoders.encode_base64(part)
    
    # Set headers
    part.add_header('Content-Disposition', disposition)
    if description:
        part.add_header('Content-Description', description)
    
    msg.attach(part)

def send_with_file(**kwargs):
    """
    Send email with a single file attachment
    Compatible with Mail::Sender's MailFile method
    """
    smtp_host = kwargs.get('smtp_host', 'localhost')
    from_addr = kwargs['from']
    to_addr = kwargs['to']
    subject = kwargs.get('subject', '')
    message = kwargs.get('msg', '')
    file_path = kwargs['file']
    
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")
    
    # Prepare attachment info
    attachments = [{
        'file': file_path,
        'ctype': mimetypes.guess_type(file_path)[0] or 'application/octet-stream',
        'encoding': 'base64',
        'disposition': f'attachment; filename={os.path.basename(file_path)}'
    }]
    
    # Use send_multipart
    return send_multipart(
        smtp_host=smtp_host,
        from_addr=from_addr,
        to=to_addr,
        subject=subject,
        body=message,
        attachments=attachments
    )

def send_simple(**kwargs):
    """
    Send simple text email without attachments
    Compatible with Mail::Sender's MailMsg method
    """
    smtp_host = kwargs.get('smtp_host', 'localhost')
    smtp_port = kwargs.get('smtp_port', 25)
    from_addr = kwargs.get('from')
    to_addr = kwargs.get('to')
    subject = kwargs.get('subject', '')
    message = kwargs.get('msg', '')
    
    if not from_addr or not to_addr:
        raise ValueError("From and To addresses are required")
    
    # Handle multiple recipients
    if isinstance(to_addr, list):
        to_list = to_addr
        to_addr = ', '.join(to_addr)
    else:
        to_list = [addr.strip() for addr in to_addr.split(',')]
    
    # Create message
    msg = MIMEText(message)
    msg['From'] = from_addr
    msg['To'] = to_addr
    msg['Subject'] = subject
    msg['Date'] = formatdate(localtime=True)
    msg['Message-ID'] = make_msgid()
    
    try:
        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.send_message(msg, from_addr, to_list)
        return {"status": "sent", "message": "Email sent successfully"}
    except Exception as e:
        raise RuntimeError(f"Failed to send email: {str(e)}")

def test_smtp_connection(**kwargs):
    """
    Test SMTP connection
    """
    smtp_host = kwargs.get('smtp_host', 'localhost')
    smtp_port = kwargs.get('smtp_port', 25)
    
    try:
        with smtplib.SMTP(smtp_host, smtp_port) as server:
            # Test connection
            status = server.noop()
            return {
                "status": "connected",
                "host": smtp_host,
                "port": smtp_port,
                "response": str(status)
            }
    except Exception as e:
        raise RuntimeError(f"SMTP connection failed: {str(e)}")

# Test function for bridge validation
def ping(**kwargs):
    """Test function to verify email module is loaded"""
    return {
        "module": "email",
        "status": "ready",
        "functions": ["send_multipart", "send_with_file", "send_simple", "test_smtp_connection"],
        "python_version": sys.version
    }
