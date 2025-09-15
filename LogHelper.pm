# File: LogHelper.pm
package LogHelper;

use strict;
use warnings;
use CPANBridge;
use Carp;

our $VERSION = '1.00';

# Global state to maintain Log::Log4perl compatibility
our $INITIALIZED = 0;
our $GLOBAL_LOGGERS = {};
our $CALLER_DEPTH = 1;

# Level constants (Log::Log4perl compatibility)
use constant {
    TRACE => 5000,
    DEBUG => 10000,
    INFO  => 20000,
    WARN  => 30000,
    ERROR => 40000,
    FATAL => 50000,
    OFF   => 60000,
};

# Export level constants and functions
sub import {
    my $class = shift;
    my $caller = caller;
    
    # Export level constants
    {
        no strict 'refs';
        *{"${caller}::TRACE"} = \&TRACE;
        *{"${caller}::DEBUG"} = \&DEBUG;
        *{"${caller}::INFO"}  = \&INFO;
        *{"${caller}::WARN"}  = \&WARN;
        *{"${caller}::ERROR"} = \&ERROR;
        *{"${caller}::FATAL"} = \&FATAL;
        *{"${caller}::OFF"}   = \&OFF;
        
        # Export get_logger function
        *{"${caller}::get_logger"} = \&get_logger;
        
        # Create Log::Log4perl compatibility
        *{"${caller}::Log::Log4perl::get_logger"} = \&get_logger;
        *{"${caller}::Log::Log4perl::initialized"} = \&initialized;
        *{"${caller}::Log::Log4perl::wrapper_register"} = \&wrapper_register;
        *{"${caller}::Log::Log4perl::appender_by_name"} = \&appender_by_name;
        *{"${caller}::Log::Log4perl::caller_depth"} = \$CALLER_DEPTH;
        
        # Create appender and layout classes
        *{"${caller}::Log::Log4perl::Appender::new"} = \&_create_appender;
        *{"${caller}::Log::Log4perl::Layout::PatternLayout::new"} = \&_create_layout;
    }
}

# Main Log::Log4perl compatibility functions
sub initialized {
    return $INITIALIZED;
}

sub get_logger {
    my ($category) = @_;
    $category ||= 'main';
    
    if (!exists $GLOBAL_LOGGERS->{$category}) {
        $GLOBAL_LOGGERS->{$category} = LogHelper::Logger->new($category);
    }
    
    return $GLOBAL_LOGGERS->{$category};
}

sub wrapper_register {
    my ($package) = @_;
    # In your usage, this is just for compatibility - no action needed
    return 1;
}

sub appender_by_name {
    my ($name) = @_;
    
    # Return a mock appender that can have its layout changed
    return LogHelper::Appender->new($name);
}

# Internal functions for appender/layout creation
sub _create_appender {
    my ($class, $type, %args) = @_;
    return LogHelper::Appender->new($args{name} || 'default', $type);
}

sub _create_layout {
    my ($class, $pattern) = @_;
    return LogHelper::Layout->new($pattern);
}

# Logger class
package LogHelper::Logger;
use strict;
use warnings;
use base 'CPANBridge';

sub new {
    my ($class, $category) = @_;
    
    my $self = $class->SUPER::new();
    
    $self->{category} = $category || 'main';
    $self->{level} = LogHelper::INFO();
    $self->{appenders} = [];
    $self->{layouts} = {};
    
    return $self;
}

# Level management (your pattern)
sub level {
    my ($self, $new_level) = @_;
    
    if (defined $new_level) {
        $self->{level} = $new_level;
    }
    
    return $self->{level};
}

sub getlevel {
    my $self = shift;
    return $self->{level};
}

# Appender management
sub add_appender {
    my ($self, $appender) = @_;
    
    push @{$self->{appenders}}, $appender;
    return $self;
}

# Logging methods (your core usage)
sub trace {
    my ($self, $message) = @_;
    $self->_log(LogHelper::TRACE(), 'TRACE', $message);
}

sub debug {
    my ($self, $message) = @_;
    $self->_log(LogHelper::DEBUG(), 'DEBUG', $message);
}

sub info {
    my ($self, $message) = @_;
    $self->_log(LogHelper::INFO(), 'INFO', $message);
}

sub warn {
    my ($self, $message) = @_;
    $self->_log(LogHelper::WARN(), 'WARN', $message);
}

sub error {
    my ($self, $message) = @_;
    $self->_log(LogHelper::ERROR(), 'ERROR', $message);
}

sub fatal {
    my ($self, $message) = @_;
    $self->_log(LogHelper::FATAL(), 'FATAL', $message);
}

sub logdie {
    my ($self, $message) = @_;
    $self->fatal($message);
    die $message;
}

# Level check methods (your is_* pattern)
sub is_trace {
    my $self = shift;
    return $self->{level} <= LogHelper::TRACE();
}

sub is_debug {
    my $self = shift;
    return $self->{level} <= LogHelper::DEBUG();
}

sub is_info {
    my $self = shift;
    return $self->{level} <= LogHelper::INFO();
}

sub is_warn {
    my $self = shift;
    return $self->{level} <= LogHelper::WARN();
}

sub is_error {
    my $self = shift;
    return $self->{level} <= LogHelper::ERROR();
}

sub is_fatal {
    my $self = shift;
    return $self->{level} <= LogHelper::FATAL();
}

# Internal logging method
sub _log {
    my ($self, $msg_level, $level_name, $message) = @_;
    
    return if $msg_level < $self->{level};
    
    # Get caller information (your enhanced formatting pattern)
    my $depth = $LogHelper::CALLER_DEPTH + 1;
    my ($package, $filename, $line) = caller($depth);
    
    # Prepare log parameters
    my $params = {
        category => $self->{category},
        level => $level_name,
        message => $message,
        filename => $filename,
        line => $line,
        package => $package,
        timestamp => time(),
        appenders => $self->{appenders},
    };
    
    # Send to Python backend for formatting and output
    my $result = $self->call_python('logging', 'log_message', $params);
    
    if (!$result->{success}) {
        # Fallback to simple print if backend fails
        warn "LogHelper backend error: " . ($result->{error} || 'unknown');
        my $timestamp = scalar localtime();
        print STDERR "[$timestamp] $level_name: $message\n";
    }
}

# Mock Appender class for compatibility
package LogHelper::Appender;
use strict;
use warnings;

sub new {
    my ($class, $name, $type) = @_;
    
    my $self = {
        name => $name || 'default',
        type => $type || 'Screen',
        layout => undef,
    };
    
    return bless $self, $class;
}

sub layout {
    my ($self, $layout) = @_;
    
    if (defined $layout) {
        $self->{layout} = $layout;
    }
    
    return $self->{layout};
}

sub name {
    my $self = shift;
    return $self->{name};
}

# Mock Layout class for compatibility
package LogHelper::Layout;
use strict;
use warnings;

sub new {
    my ($class, $pattern) = @_;
    
    my $self = {
        pattern => $pattern || '%d|%m%n',
    };
    
    return bless $self, $class;
}

sub pattern {
    my $self = shift;
    return $self->{pattern};
}

# WlaLog wrapper compatibility class
package LogHelper::WlaLog;
use strict;
use warnings;
use base 'LogHelper::Logger';

sub new {
    my ($class, $level, $module_name) = @_;
    
    $level ||= 'INFO';
    $module_name ||= 'main';
    
    # Convert level name to constant
    my $setlevel;
    if ($level eq "INFO") { $setlevel = LogHelper::INFO(); }
    elsif ($level eq "WARN") { $setlevel = LogHelper::WARN(); }
    elsif ($level eq "DEBUG") { $setlevel = LogHelper::DEBUG(); }
    elsif ($level eq "ERROR") { $setlevel = LogHelper::ERROR(); }
    elsif ($level eq "FATAL") { $setlevel = LogHelper::FATAL(); }
    elsif ($level eq "TRACE") { $setlevel = LogHelper::TRACE(); }
    else { $setlevel = LogHelper::INFO(); }
    
    # Initialize Log4perl compatibility if not done
    unless ($LogHelper::INITIALIZED) {
        $LogHelper::CALLER_DEPTH = 1;  # Your depth setting
        $LogHelper::INITIALIZED = 1;
    }
    
    # Create logger
    my $logger = LogHelper::get_logger($module_name);
    
    # Create appender (your Screen appender pattern)
    my $appender = LogHelper::Appender->new("sysout", "Screen");
    
    # Create layout (your standard layout pattern)
    my $layout = LogHelper::Layout->new("%d{EEE yyyy/MM/dd HH:mm:ss}|%m%n");
    $appender->layout($layout);
    
    # Add appender and set level
    $logger->add_appender($appender);
    $logger->level($setlevel);
    
    # Store original layout for reset functionality
    $logger->{LAYOUT} = $layout;
    
    return bless $logger, $class;
}

sub getlogger {
    # Static method to get main logger
    return LogHelper::get_logger("main");
}

# Enhanced logging methods with your formatting patterns
sub debug {
    my ($self, $text) = @_;
    
    # Your enhanced debug formatting
    my ($package, $filename, $line) = caller();
    my $dbginfo = sprintf("DEBUG: %s line:%s: %s", $filename, $line, $text);
    
    # Temporary layout change for debug
    $self->_set_debug_layout();
    $self->SUPER::debug($dbginfo);
    $self->_restore_original_layout();
}

sub error {
    my ($self, $text) = @_;
    
    # Your error formatting
    my ($package, $filename, $line) = caller();
    my $dbginfo = sprintf("%s line:%s: %s", $filename, $line, $text);
    
    # Temporary layout change for error
    $self->_set_debug_layout();
    $self->SUPER::error($dbginfo);
    $self->_restore_original_layout();
}

sub fatal {
    my ($self, $text) = @_;
    
    # Your fatal formatting
    my ($package, $filename, $line) = caller();
    my $dbginfo = sprintf("%s line:%s: %s", $filename, $line, $text);
    
    # Temporary layout change for fatal
    $self->_set_debug_layout();
    $self->SUPER::fatal($dbginfo);
    $self->_restore_original_layout();
}

sub logdie {
    my ($self, $text) = @_;
    
    # Your logdie formatting
    my ($package, $filename, $line) = caller();
    my $dbginfo = sprintf("LOGANDDIE> %s line:%s: %s \n\tExiting program %s",
                          $filename, $line, $text, $filename);
    
    $self->_set_debug_layout();
    $self->SUPER::fatal($dbginfo);
    $self->_restore_original_layout();
    
    die $text;  # Exit after logging
}

# Your "always log" functionality
sub always {
    my ($self, $text) = @_;
    
    my $current_level = $self->getlevel();
    $self->level(LogHelper::TRACE());  # Lowest level to ensure logging
    $self->trace($text);
    $self->level($current_level);  # Reset to original level
}

# Layout switching methods (your pattern)
sub _set_debug_layout {
    my $self = shift;
    
    # Your debug layout pattern
    my $debuglayout = LogHelper::Layout->new("%d|%p> %m%n");
    
    # Simulate getting appender by name and changing layout
    if (@{$self->{appenders}}) {
        $self->{appenders}->[0]->layout($debuglayout);
    }
}

sub _restore_original_layout {
    my $self = shift;
    
    # Restore original layout
    my $orig_layout = $self->{LAYOUT};
    if (@{$self->{appenders}} && $orig_layout) {
        $self->{appenders}->[0]->layout($orig_layout);
    }
}

# Level check methods with proper blessing (your pattern)
sub is_trace {
    my $self = shift;
    my $logger = LogHelper::get_logger("main");
    bless($logger, "LogHelper::Logger");
    return $logger->is_trace();
}

sub is_debug {
    my $self = shift;
    my $logger = LogHelper::get_logger("main");
    bless($logger, "LogHelper::Logger");
    return $logger->is_debug();
}

sub is_info {
    my $self = shift;
    my $logger = LogHelper::get_logger("main");
    bless($logger, "LogHelper::Logger");
    return $logger->is_info();
}

sub is_warn {
    my $self = shift;
    my $logger = LogHelper::get_logger("main");
    bless($logger, "LogHelper::Logger");
    return $logger->is_warn();
}

sub is_error {
    my $self = shift;
    my $logger = LogHelper::get_logger("main");
    bless($logger, "LogHelper::Logger");
    return $logger->is_error();
}

sub is_fatal {
    my $self = shift;
    my $logger = LogHelper::get_logger("main");
    bless($logger, "LogHelper::Logger");
    return $logger->is_fatal();
}

1;

__END__

=head1 NAME

LogHelper - Log::Log4perl replacement using Python backend with WlaLog wrapper compatibility

=head1 SYNOPSIS

    # Replace: use Log::Log4perl qw(get_logger :levels :no_extra_logdie_message);
    use LogHelper qw(get_logger :levels);
    
    # Your WlaLog wrapper pattern works unchanged:
    my $l = CPS::WlaLog->new("WARN");
    $l->info("Application started");
    $l->debug("Variable value: $var");
    $l->error("Database connection failed");
    
    # Direct Log::Log4perl compatibility:
    unless (Log::Log4perl->initialized) {
        my $logger = Log::Log4perl->get_logger("main");
        my $appender = Log::Log4perl::Appender->new("Log::Log4perl::Appender::Screen",name => "sysout");
        my $layout = Log::Log4perl::Layout::PatternLayout->new("%d{EEE yyyy/MM/dd HH:mm:ss}|%m%n");
        $appender->layout($layout);
        $logger->add_appender($appender);
        $logger->level($INFO);
    }
    
    # Static logger access:
    my $ll = CPS::WlaLog->getlogger();
    $ll->info("informational message");

=head1 DESCRIPTION

LogHelper provides a drop-in replacement for Log::Log4perl with full compatibility
for the CPS::WlaLog wrapper pattern found in your codebase.

Supports all patterns from your usage analysis:
- Programmatic initialization and configuration
- WlaLog wrapper with enhanced message formatting
- Screen appender with multiple layout patterns
- All log levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL
- Level checking methods (is_debug, is_info, etc.)
- Caller depth management and enhanced debugging
- Layout switching for different message types
- Always-log functionality that bypasses level restrictions

=head1 MIGRATION

Change only the use statement:
- Replace 'use Log::Log4perl ...' with 'use LogHelper ...'

Your CPS::WlaLog wrapper and all Log::Log4perl usage works unchanged.

=head1 SEE ALSO

L<CPANBridge>, L<Log::Log4perl>

=cut