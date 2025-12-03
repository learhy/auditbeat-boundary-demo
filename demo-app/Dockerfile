FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    vim \
    sudo \
    openssh-client \
    netcat \
    htop \
    && rm -rf /var/lib/apt/lists/*

# Create demo user
RUN useradd -m -s /bin/bash demouser && \
    echo 'demouser:boundary123' | chpasswd && \
    usermod -aG sudo demouser

# Create some demo files
RUN mkdir -p /home/demouser/sensitive && \
    echo "confidential data" > /home/demouser/sensitive/secret.txt && \
    echo "financial records" > /home/demouser/sensitive/finance.csv && \
    chown -R demouser:demouser /home/demouser/

WORKDIR /home/demouser
USER demouser

CMD ["tail", "-f", "/dev/null"]
