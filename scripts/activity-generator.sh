#!/bin/bash

# Create log directory
mkdir -p /tmp/audit-demo

LOG_FILE="/tmp/audit-demo/boundary-activity.log"
DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo "Starting activity generator..."

# Function to log activity with structured format
log_activity() {
    local timestamp="$1"
    local event_type="$2" 
    local action="$3"
    local user="$4"
    local details="$5"
    local session_id="boundary-session-$(date +%s)"
    
    echo "{
  \"@timestamp\": \"$timestamp\",
  \"event\": {
    \"action\": \"$action\",
    \"category\": \"$event_type\",
    \"type\": \"audit\"
  },
  \"user\": {
    \"name\": \"$user\",
    \"id\": \"$(id -u 2>/dev/null || echo 1000)\"
  },
  \"session\": {
    \"id\": \"$session_id\"
  },
  \"boundary\": {
    \"session_id\": \"$session_id\",
    \"target_type\": \"ssh\",
    \"user_id\": \"u_1234567890\",
    \"target_id\": \"ttcp_0987654321\"
  },
  \"process\": {
    \"title\": \"$action\",
    \"working_directory\": \"/tmp\"
  },
  \"message\": \"$details\"
}" >> $LOG_FILE
}

# Function to simulate different types of activity
generate_activity() {
    local scenario=$1
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    echo "Running scenario $scenario"
    
    case $scenario in
        1) # Normal user activity
            echo "=== Scenario 1: Normal user activity ==="
            log_activity "$timestamp" "file" "file_create" "demo-user" "Normal file operations in user session"
            touch /tmp/user_file.txt
            echo "Normal user operation" > /tmp/user_file.txt
            log_activity "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" "file" "file_read" "demo-user" "Reading user-created file"
            cat /tmp/user_file.txt
            log_activity "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" "file" "file_delete" "demo-user" "Cleaning up user file"
            rm /tmp/user_file.txt
            ;;
        2) # Privilege escalation attempt
            echo "=== Scenario 2: Privilege escalation ==="
            log_activity "$timestamp" "authentication" "privilege_escalation_attempt" "demo-user" "Attempted sudo access - potential privilege escalation"
            sudo -l 2>/dev/null || echo "Attempted sudo access"
            log_activity "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" "authentication" "su_attempt" "demo-user" "Attempted su to root - privilege escalation detected"
            su - root -c "echo 'Root access attempt'" 2>/dev/null || echo "Attempted su to root"
            ;;
        3) # Suspicious file access
            echo "=== Scenario 3: Suspicious file access ==="
            log_activity "$timestamp" "file" "sensitive_file_access" "demo-user" "Attempted to read /etc/passwd - sensitive file access"
            cat /etc/passwd 2>/dev/null || echo "Attempted to read /etc/passwd"
            log_activity "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" "file" "sensitive_file_access" "demo-user" "Attempted to read /etc/shadow - highly suspicious activity"
            cat /etc/shadow 2>/dev/null || echo "Attempted to read /etc/shadow"
            log_activity "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" "file" "directory_enumeration" "demo-user" "Attempted to list /root directory - reconnaissance activity"
            ls -la /root/ 2>/dev/null || echo "Attempted to list /root directory"
            ;;
        4) # Network reconnaissance
            echo "=== Scenario 4: Network reconnaissance ==="
            log_activity "$timestamp" "network" "network_enumeration" "demo-user" "Network reconnaissance - listing active connections"
            netstat -an 2>/dev/null || echo "Attempted network enumeration"
            log_activity "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" "process" "process_enumeration" "demo-user" "Process enumeration - gathering system information"
            ps aux 2>/dev/null || echo "Attempted process enumeration"
            ;;
        5) # Run all scenarios
            echo "=== Running all scenarios ==="
            generate_activity 1
            sleep 5
            generate_activity 2
            sleep 5
            generate_activity 3
            sleep 5
            generate_activity 4
            ;;
        *) 
            echo "Unknown scenario: $scenario"
            echo "Usage: $0 [1-5]"
            echo "1: Normal activity"
            echo "2: Privilege escalation"
            echo "3: Suspicious file access" 
            echo "4: Network reconnaissance"
            echo "5: All scenarios"
            ;;
    esac
}

# Default to running all scenarios if no argument provided
SCENARIO=${1:-5}
generate_activity $SCENARIO

echo "Activity generation complete. Log file created at: $LOG_FILE"
echo "Generated $(wc -l < $LOG_FILE) log lines"
