#!/bin/bash
set -e

COMMAND="${1:-}"

show_usage() {
    echo "Usage: $0 {start|stop|restart|status}"
    echo ""
    echo "Commands:"
    echo "  start   - Start the demo (Boundary + Docker containers)"
    echo "  stop    - Stop the demo"
    echo "  restart - Stop and start the demo"
    echo "  status  - Show status of all components"
    exit 1
}

start_demo() {
    echo "🚀 Starting Boundary SSH Certificate Injection Demo"
    echo "===================================================="
    echo ""

    # Check if boundary is installed
    if ! command -v boundary &> /dev/null; then
        echo "❌ Boundary CLI not found. Please install it first:"
        echo "   See README.md for installation instructions"
        exit 1
    fi

    # Check if boundary is Enterprise version
    BOUNDARY_VERSION=$(boundary version 2>&1)
    if ! echo "$BOUNDARY_VERSION" | grep -qi "ent"; then
        echo "❌ Boundary Enterprise is required for this demo."
        echo "   Current version:"
        echo "$BOUNDARY_VERSION" | head -5
        echo ""
        echo "   Please install Boundary Enterprise:"
        echo "   macOS Apple Silicon:"
        echo "     wget https://releases.hashicorp.com/boundary/0.19.3+ent/boundary_0.19.3+ent_darwin_arm64.zip"
        echo "     unzip boundary_0.19.3+ent_darwin_arm64.zip"
        echo "     sudo mv boundary /usr/local/bin/"
        echo ""
        echo "   macOS Intel:"
        echo "     wget https://releases.hashicorp.com/boundary/0.19.3+ent/boundary_0.19.3+ent_darwin_amd64.zip"
        echo "     unzip boundary_0.19.3+ent_darwin_amd64.zip"
        echo "     sudo mv boundary /usr/local/bin/"
        exit 1
    fi
    VERSION_LINE=$(echo "$BOUNDARY_VERSION" | grep "Version Number" | awk '{print $NF}')
    echo "✅ Found Boundary Enterprise: $VERSION_LINE"

    # Check if docker-compose is running
    if ! docker info &> /dev/null; then
        echo "❌ Docker is not running. Please start Docker Desktop."
        exit 1
    fi

    # Kill any existing boundary dev processes
    echo "🧹 Cleaning up existing processes..."
    pkill -f "boundary dev" 2>/dev/null || true
    sleep 2

    # Tear down existing containers
    echo "🧹 Cleaning up existing containers..."
    docker-compose down -v

    # Start Docker containers (they will wait for Boundary)
    echo "🐳 Starting Docker containers..."
    docker-compose up -d

    # Wait a moment for containers to initialize
    sleep 5

    # Start Boundary dev in the background
    echo "🎯 Starting Boundary dev..."
    if [ -f "boundary-license.hclic" ]; then
        echo "   (Loading Enterprise license)"
        export BOUNDARY_LICENSE=$(cat boundary-license.hclic)
        # Make the dev worker reachable from Docker containers by advertising a
        # public address on the host and binding the proxy listener on 0.0.0.0.
        export BOUNDARY_DEV_WORKER_PUBLIC_ADDRESS="host.docker.internal:9202"
        export BOUNDARY_DEV_WORKER_PROXY_LISTEN_ADDRESS="0.0.0.0:9202"
        nohup boundary dev > boundary-dev.log 2>&1 &
    else
        echo "   ⚠️  No license file found (boundary-license.hclic)"
        echo "   Boundary Enterprise requires a license"
        exit 1
    fi

    BOUNDARY_PID=$!
    echo "   Boundary dev started (PID: $BOUNDARY_PID)"

    # Wait for Boundary to be ready
    echo "⏳ Waiting for Boundary to be ready..."
    for i in {1..30}; do
        if curl -sf http://localhost:9200/v1/scopes > /dev/null 2>&1; then
            echo "✅ Boundary is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "❌ Boundary failed to start. Check boundary-dev.log"
            exit 1
        fi
        sleep 1
    done
    
    # Clear any stale target IDs from previous runs (must be done while containers are running)
    echo "🧹 Clearing stale configuration..."
    docker-compose exec -T activity-generator rm -f /shared/target-id /shared/auth-method-id 2>/dev/null || true
    
    # Trigger boundary-setup to configure Boundary
    echo "⚛️  Configuring Boundary with SSH targets..."
    docker-compose restart boundary-setup

    # Wait for configuration to complete
    sleep 35

    # Get the target ID
    TARGET_ID=$(docker-compose exec -T activity-generator cat /shared/target-id 2>/dev/null | tr -d '\r\n')
    if [ -z "$TARGET_ID" ]; then
        echo "❌ Failed to get target ID from boundary-setup"
        echo "   Check logs: docker-compose logs boundary-setup"
        exit 1
    fi

    echo ""
    echo "✅ Demo is ready!"
    echo "===================================================="
    echo "🎯 Target ID: $TARGET_ID"
    echo ""
    echo "📋 Useful commands:"
    echo "   # View Boundary logs"
    echo "   tail -f boundary-dev.log"
    echo ""
    echo "   # View SSH session activity"
    echo "   docker-compose logs -f activity-generator"
    echo ""
    echo "   # Test SSH connection manually"
    echo "   boundary authenticate password -auth-method-id ampw_1234567890 -login-name admin -password password"
    echo "   boundary connect ssh -target-id $TARGET_ID -username ubuntu"
    echo ""
    echo "   # View audit events in Elasticsearch"
    echo "   curl -s http://localhost:9300/auditbeat-*/_search | jq ."
    echo ""
    echo "   # Access Kibana"
    echo "   open http://localhost:5601"
    echo ""
    echo "   # Check status"
    echo "   ./auditbeat-demo.sh status"
    echo ""
    echo "   # Stop everything"
    echo "   ./auditbeat-demo.sh stop"
    echo ""
    echo "===================================================="
}

stop_demo() {
    echo "🛑 Stopping Boundary SSH Certificate Injection Demo"
    echo "===================================================="

    # Stop Boundary dev
    echo "🎯 Stopping Boundary dev..."
    pkill -f "boundary dev" 2>/dev/null || true

    # Stop Docker containers
    echo "🐳 Stopping Docker containers..."
    docker-compose down

    echo ""
    echo "✅ Demo stopped!"
    echo ""
    echo "To start again: ./auditbeat-demo.sh start"
    echo "To clean everything (including Boundary database): docker-compose down -v && rm -rf .boundary-data"
}

show_status() {
    echo "📊 Demo Status"
    echo "===================================================="
    echo ""
    
    # Check Boundary
    if pgrep -f "boundary dev" > /dev/null; then
        BOUNDARY_PID=$(pgrep -f "boundary dev")
        echo "✅ Boundary dev: Running (PID: $BOUNDARY_PID)"
        if curl -sf http://localhost:9200/v1/scopes > /dev/null 2>&1; then
            echo "   API: Responding on http://localhost:9200"
        else
            echo "   ⚠️  API: Not responding"
        fi
    else
        echo "❌ Boundary dev: Not running"
    fi
    echo ""
    
    # Check Docker containers
    echo "🐳 Docker Containers:"
    docker-compose ps
    echo ""

    # Check target ID
    TARGET_ID=$(docker-compose exec -T activity-generator cat /shared/target-id 2>/dev/null | tr -d '\r\n' || echo "")
    if [ -n "$TARGET_ID" ]; then
        echo "🎯 Current Target ID: $TARGET_ID"
    else
        echo "⚠️  No target ID found"
    fi

    # Check Auditbeat on SSH target
    if docker-compose exec -T ssh-target pgrep auditbeat >/dev/null 2>&1; then
        echo "🛡  Auditbeat on ssh-target: Running"
    else
        echo "⚠️  Auditbeat on ssh-target: Not running (check ssh-target logs)"
    fi

    echo ""
    echo "===================================================="
}

case "$COMMAND" in
    start)
        start_demo
        ;;
    stop)
        stop_demo
        ;;
    restart)
        stop_demo
        echo ""
        sleep 2
        start_demo
        ;;
    status)
        show_status
        ;;
    *)
        show_usage
        ;;
esac
