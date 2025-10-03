#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Package metadata
PACKAGE_NAME="opennic-up"
VERSION="dev-20251003-200505"
ARCHITECTURE="amd64"
MAINTAINER="kewlfft"
DESCRIPTION="OpenNIC auto DNS updater"

# Required dependencies for building .deb packages
REQUIRED_DEPS=("dpkg-deb")

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    local missing_packages=()
    
    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
            # Map commands to package names
            case "$dep" in
                dpkg-deb)
                    missing_packages+=("dpkg-dev")
                    ;;
                *)
                    missing_packages+=("$dep")
                    ;;
            esac
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warn "Missing dependencies detected!"
        echo "The following commands are required but not found:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "The following packages need to be installed:"
        for pkg in "${missing_packages[@]}"; do
            echo "  - $pkg"
        done
        echo ""
        
        read -p "Do you want to install these packages automatically? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installing missing packages..."
            sudo apt-get update
            sudo apt-get install -y "${missing_packages[@]}"
            print_info "Dependencies installed successfully!"
        else
            print_error "Cannot proceed without required dependencies. Exiting."
            exit 1
        fi
    else
        print_info "All required dependencies are present."
    fi
}

# Verify source files exist
verify_source_files() {
    local missing_files=()
    local required_files=("opennic-up" "opennic-up.conf" "opennic-up.service" "opennic-up.timer")
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "Missing required source files:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        exit 1
    fi
    
    print_info "All source files found."
}

# Create the .deb package structure
create_package_structure() {
    BUILD_DIR="${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}"
    
    print_info "Creating package structure in $BUILD_DIR..."
    
    # Create directory structure
    mkdir -p "$BUILD_DIR/DEBIAN"
    mkdir -p "$BUILD_DIR/usr/local/bin"
    mkdir -p "$BUILD_DIR/etc/opennic-up"
    mkdir -p "$BUILD_DIR/lib/systemd/system"
    
    # Copy files to appropriate locations
    print_info "Copying files..."
    cp opennic-up "$BUILD_DIR/usr/local/bin/"
    chmod 755 "$BUILD_DIR/usr/local/bin/opennic-up"
    
    cp opennic-up.conf "$BUILD_DIR/etc/opennic-up/"
    chmod 644 "$BUILD_DIR/etc/opennic-up/opennic-up.conf"
    
    cp opennic-up.service "$BUILD_DIR/lib/systemd/system/"
    chmod 644 "$BUILD_DIR/lib/systemd/system/opennic-up.service"
    
    cp opennic-up.timer "$BUILD_DIR/lib/systemd/system/"
    chmod 644 "$BUILD_DIR/lib/systemd/system/opennic-up.timer"
    
    # Create control file
    cat > "$BUILD_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Description: $DESCRIPTION
 This package provides the OpenNIC DNS updater service with systemd integration.
 It includes a timer for automatic updates.
EOF
    
    # Create postinst script (runs after installation)
    cat > "$BUILD_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

# Reload systemd daemon
systemctl daemon-reload

# Enable and start the timer
systemctl enable opennic-up.timer
systemctl start opennic-up.timer

echo "OpenNIC updater timer has been enabled and started."
echo "Use 'systemctl status opennic-up.timer' to check its status."

exit 0
EOF
    chmod 755 "$BUILD_DIR/DEBIAN/postinst"
    
    # Create prerm script (runs before removal)
    cat > "$BUILD_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e

# Stop and disable the timer
systemctl stop opennic-up.timer 2>/dev/null || true
systemctl disable opennic-up.timer 2>/dev/null || true

# Stop the service if running
systemctl stop opennic-up.service 2>/dev/null || true

exit 0
EOF
    chmod 755 "$BUILD_DIR/DEBIAN/prerm"
    
    # Create postrm script (runs after removal)
    cat > "$BUILD_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e

# Reload systemd daemon
systemctl daemon-reload

exit 0
EOF
    chmod 755 "$BUILD_DIR/DEBIAN/postrm"
    
    print_info "Package structure created successfully."
}

# Build the .deb package
build_package() {
    local output_file="${BUILD_DIR}.deb"
    
    print_info "Building .deb package..."
    
    dpkg-deb --build --root-owner-group "$BUILD_DIR"
    
    if [ -f "$output_file" ]; then
        print_info "Package built successfully: $output_file"
        echo ""
        echo "Package information:"
        dpkg-deb --info "$output_file"
        echo ""
        echo "To install the package, run:"
        echo "  sudo dpkg -i $output_file"
        echo ""
        echo "To remove the package, run:"
        echo "  sudo dpkg -r $PACKAGE_NAME"
    else
        print_error "Package build failed!"
        exit 1
    fi
}

# Main execution
main() {
    print_info "Starting .deb package creation for $PACKAGE_NAME..."
    echo ""
    
    # Check dependencies
    check_dependencies
    echo ""
    
    # Verify source files
    verify_source_files
    echo ""
    
    # Create package structure
    create_package_structure
    echo ""
    
    # Build the package
    build_package
    
    print_info "Build process completed!"
}

# Run main function
main
