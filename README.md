# SERP Hawk CRM V2

AI-powered CRM platform for SEO agencies, built with Next.js, FastAPI, PostgreSQL, and Docker.

---

# 1. Project Overview
Architecture overview

Layer 1 — CI/CD and provisioning. GitHub Actions (running both the application CI/CD pipeline and Terraform) authenticates to AWS entirely through OIDC federation into a single scoped IAM role — no long-lived access keys are stored anywhere. That role is used three ways: to manage Terraform's own state (S3, with DynamoDB for locking, so two pipeline runs can never corrupt state by applying concurrently), to read and write secrets in SSM Parameter Store (currently the SonarQube database password), and to provision the actual AWS resources below.

GitHub ActionsCI/CD + Terraform, OIDC
AWS IAM roleGitHub Actions role (OIDC)
Terraform stateS3 + DynamoDB locking
SSM Parameter StoreDB password secrets
AWS resourcesEC2s + ECR

Layer 2 — application infrastructure. Terraform provisions this layer as two independent environments, each with its own state file (serp-hawk/prod.tfstate and serp-hawk/sonarqube.tfstate), so applying one never risks the other. The app server runs Amazon Linux 2023 on a t3.medium with a 20GB root volume, an Elastic IP, and a security group open on ports 3000 and 8000 (SSH disabled by default — management goes through SSM only). Its IAM role grants read-only ECR access, nothing broader. The SonarQube server runs Ubuntu with its own local PostgreSQL database for SonarQube's internal metadata, entirely separate from the application's data.

Amazon ECRDocker image registry
SonarQube EC2Nginx :80 to SonarQube:9000
App server EC2Next.js :3000, FastAPI :8000
Neon PostgreSQLManaged database(external)

A separate deployment workflow (deploy.yml) pulls the images ECR just received onto the app server via AWS Systems Manager Run Command — no SSH keys involved at any point. The application itself connects to Neon, a managed serverless PostgreSQL database, kept as the single source of truth for application data throughout this deployment rather than self-hosting a database for it.

SERP Hawk CRM V2 is a full-stack CRM application designed for SEO agencies.

The application consists of:

* **Frontend:** Next.js 16 / React 19 / TypeScript / Tailwind CSS
* **Backend:** FastAPI / Python 3.13 / SQLModel / Uvicorn
* **Database:** PostgreSQL hosted on Neon
* **Containerization:** Docker
* **Container orchestration:** Docker Compose
* **CI/CD:** GitHub Actions
* **Container registry:** Amazon ECR
* **Application hosting:** Amazon EC2
* **EC2 management:** AWS Systems Manager (SSM)
* **AWS authentication:** GitHub OIDC + AWS IAM

---

# 2. AWS Architecture

The deployment architecture follows this flow:

```text
Developer
    |
    | git push
    v
GitHub Repository
    |
    v
GitHub Actions
    |
    | GitHub OIDC
    v
AWS IAM Role
    |
    | Build & Push
    v
+-----------------------------+
|        Amazon ECR           |
|                             |
|  serphawk-backend           |
|  serphawk-frontend          |
+--------------+--------------+
               |
               | Pull Images
               v
+--------------------------------------+
|              AWS EC2                |
|                                      |
|          Docker Compose              |
|                                      |
|   +----------------------------+     |
|   | Frontend Container         |     |
|   | Next.js                    |     |
|   | Port 3000                  |     |
|   +----------------------------+     |
|                                      |
|   +----------------------------+     |
|   | Backend Container          |     |
|   | FastAPI / Uvicorn          |     |
|   | Port 8000                  |     |
|   +----------------------------+     |
+------------------+-------------------+
                   |
                   | PostgreSQL
                   v
          Neon PostgreSQL

AWS Systems Manager
        |
        | Secure EC2 management
        v
       EC2

GitHub Actions
        |
        | OIDC
        v
    AWS IAM Role
```
<img width="1536" height="1024" alt="final_img" src="https://github.com/user-attachments/assets/0a2137d0-2a5f-4374-b2cb-5ce3f2c7805f" />



---

# 3. Deployment Flow

The deployment process is:

1. Developer pushes code to the `cicd` branch.
2. GitHub Actions starts the CI/CD workflow.
3. GitHub Actions authenticates with AWS using GitHub OIDC.
4. AWS IAM validates the OIDC identity and provides temporary AWS credentials.
5. GitHub Actions logs in to Amazon ECR.
6. The backend Docker image is built.
7. The frontend Docker image is built.
8. Both images are pushed to Amazon ECR.
9. EC2 pulls the latest images from ECR.
10. Docker Compose starts the frontend and backend containers.
11. The application connects to the Neon PostgreSQL database.
12. Users access the deployed application through the EC2-hosted application.

---

# 4. AWS Services

## AWS services used and why

| Service | Purpose | Why this, not the alternative |
|---|---|---|
| **EC2 (app server)** | Hosts the CRM frontend and backend as Docker containers — Amazon Linux 2023, t3.medium, Elastic IP, SSH disabled (SSM-only management), IAM role scoped to read-only ECR access | Free Tier eligible; simplest way to run a full-stack containerized app without the added cost/complexity of ECS or EKS for a project this size |
| **EC2 (SonarQube server)** | Hosts a self-managed SonarQube Community Edition instance for code quality analysis | Free Community Edition needs its own compute; running it on a dedicated t3.medium keeps it isolated from the app server's resources so a heavy scan never competes with the running application |
| **Amazon ECR** | Private Docker image registry | Integrates natively with IAM/OIDC (no separate registry credentials to manage) and with the AWS CLI tooling already used throughout the pipeline |
| **AWS Systems Manager (SSM)** | Remote command execution for deployment, and Parameter Store for secrets | Lets the CI pipeline deploy to EC2 without opening SSH to the internet or storing an SSH private key as a GitHub secret — authorization is entirely IAM-based |
| **IAM + OIDC** | Authenticates GitHub Actions to AWS | Issues short-lived (~1 hour) credentials scoped to this exact repository, instead of long-lived `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` secrets that never expire and are a larger risk if leaked |
| **S3 + DynamoDB** | Terraform remote state storage and state locking | Keeps infrastructure state out of the repository, versioned and encrypted, with DynamoDB preventing two pipeline runs from corrupting state by applying concurrently |
| **Security Groups** | Network-level firewalling per instance | Configured with least privilege — SSH restricted rather than open to `0.0.0.0/0`, and only the ports each service actually needs are opened |
| **Neon (PostgreSQL)** | Application database | Free-tier managed Postgres with no server to patch or back up manually; kept as the database of record throughout this deployment rather than migrating to a self-hosted alternative |


Why not a full high-availability setup

A production system with real traffic would warrant an Application Load Balancer across multiple Availability Zones, an Auto Scaling Group, and Multi-AZ RDS. That wasn't built here for two reasons: cost (an ALB, NAT Gateway, and Multi-AZ RDS all fall outside AWS Free Tier, adding roughly $60–80/month with no live traffic to justify it yet), and time (a multi-AZ VPC with load balancing takes meaningfully longer to build and verify than a single-instance deployment within this assignment's window). The single-EC2-per-service approach here is the pragmatic trade-off for a working, secured, take-home deployment — the HA design is the documented next step once real traffic exists to justify the added cost.

---

# 5. GitHub OIDC Authentication

The CI/CD pipeline does not require long-lived AWS access keys to be stored in GitHub.

Instead, GitHub Actions uses OpenID Connect (OIDC) to authenticate with AWS.

The authentication flow is:

```text
GitHub Actions
      |
      | OIDC Token
      v
AWS STS
      |
      | AssumeRoleWithWebIdentity
      v
AWS IAM Role
      |
      v
Temporary AWS Credentials
```

This avoids storing a permanent:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

inside the GitHub repository.

The GitHub Actions workflow uses the AWS IAM role configured for the repository.

---

# 6. GitHub Actions Configuration

The CI/CD workflow is triggered from the deployment branch:

```text
cicd
```

The workflow performs the following operations:

```text
Checkout source code
        |
        v
Configure AWS credentials
using GitHub OIDC
        |
        v
Login to Amazon ECR
        |
        v
Build backend image
        |
        v
Push backend image
        |
        v
Build frontend image
        |
        v
Push frontend image
```

The AWS account ID is maintained as a GitHub repository variable.

The IAM role ARN is maintained as a GitHub repository secret.

Example configuration:

```text
GitHub Variables

AWS_ACCOUNT_ID
```

```text
GitHub Secrets

AWS_CI_ROLE_ARN
```

No permanent AWS access key is required by the workflow.

---

# 7. Docker Images

The application is divided into two Docker images.

## Backend

ECR repository:

```text
serphawk-backend
```

The backend runs the FastAPI application using Uvicorn.

Default application port:

```text
8000
```

## Frontend

ECR repository:

```text
serphawk-frontend
```

The frontend runs the Next.js application.

Default application port:

```text
3000
```

---

# 8. Docker Compose

Docker Compose is used on the EC2 instance to run the application containers.

The deployment contains two primary services:

```yaml
services:
  backend:
    image: <ECR-BACKEND-IMAGE>

  frontend:
    image: <ECR-FRONTEND-IMAGE>
```

The containers communicate through the Docker Compose network.

The frontend is configured to communicate with the backend API using the configured API base URL.

---

# 9. EC2 Deployment

The EC2 instance is responsible for running the production containers.

After the images are available in ECR, the EC2 host authenticates with ECR and pulls the required images.

Typical deployment commands are:

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login \
  --username AWS \
  --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

Pull the latest images:

```bash
docker compose pull
```

Start the application:

```bash
docker compose up -d
```

Check running containers:

```bash
docker ps
```

Check Docker Compose services:

```bash
docker compose ps
```

View application logs:

```bash
docker compose logs -f
```

---

# 10. AWS Systems Manager

AWS Systems Manager (SSM) is used to manage the EC2 instance without depending on traditional SSH access.

SSM can be used for:

* Secure session access
* Running commands on EC2
* Server administration
* Troubleshooting
* Deployment operations

The management flow is:

```text
AWS Systems Manager
        |
        v
     EC2 Instance
        |
        v
Docker / Docker Compose
```

This provides a centralized AWS-native method of managing the deployment server.

---

# 11. Database

The application uses PostgreSQL as its database.

The database is hosted using:

```text
Neon PostgreSQL
```

The EC2 containers connect to the database using the configured database connection string.

Database credentials and connection strings must not be committed to GitHub.

Use environment variables instead.

Example:

```env
DATABASE_URL=<POSTGRESQL_CONNECTION_STRING>
```

---

# 12. Environment Variables

Environment-specific configuration should be provided through environment variables.

Create a local production environment file on the server rather than committing secrets to GitHub.

Example:

```env
DATABASE_URL=
SECRET_KEY=
NEXT_PUBLIC_API_BASE_URL=
```

Additional application-specific variables should be added according to the requirements of the backend and frontend.

> **Important:** Never commit `.env` files containing production passwords, API keys, database credentials, JWT secrets, or other sensitive information.

A safe template can be maintained as:

```text
.env.example
```

---

# 13. Required GitHub Configuration

The GitHub repository requires the following configuration.

## GitHub Variable

```text
AWS_ACCOUNT_ID
```

Value:

```text
<YOUR_AWS_ACCOUNT_ID>
```

## GitHub Secret

```text
AWS_CI_ROLE_ARN
```

Value:

```text
arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/github-actions-ecr-push-role
```

The actual AWS account ID and role ARN should not be hard-coded into public documentation if the repository is public.

---

# 14. IAM OIDC Trust Relationship

The IAM role is configured to trust GitHub's OIDC provider.

The trust relationship restricts the role to the intended GitHub repository and deployment branch.

Repository:

```text
mrurz10/SERP-Hawk-CRM-V2
```

Deployment branch:

```text
cicd
```

The expected GitHub subject is:

```text
repo:mrurz10/SERP-Hawk-CRM-V2:ref:refs/heads/cicd
```

The OIDC audience is:

```text
sts.amazonaws.com
```

This restricts the role's OIDC trust to the intended GitHub Actions workflow context.

---

# 15. ECR Repositories

The deployment uses two ECR repositories:

```text
serphawk-backend
serphawk-frontend
```

Example ECR image locations:

```text
<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/serphawk-backend:latest
```

```text
<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/serphawk-frontend:latest
```

The GitHub Actions pipeline builds and pushes the images to these repositories.

---

# 16. EC2 Security

The EC2 Security Group controls inbound and outbound network access.

Only the ports required by the application should be exposed publicly.

For the current Docker deployment:

```text
Frontend: 3000
Backend:  8000
```

If a reverse proxy or domain is configured, public traffic can instead be routed through the appropriate HTTP/HTTPS ports.

For production environments, unnecessary ports should not be exposed to the public internet.

---

# 17. Deployment Verification

After deployment, verify the EC2 containers:

```bash
docker ps
```

Expected services:

```text
serp-hawk-frontend
serp-hawk-backend
```

Check the frontend:

```text
http://<EC2-PUBLIC-IP>:3000
```

Check the backend:

```text
http://<EC2-PUBLIC-IP>:8000
```

If a domain/reverse proxy is configured, use the production domain instead.

Check logs:

```bash
docker compose logs frontend
```

```bash
docker compose logs backend
```

---

# 18. Updating the Application

To deploy a new version:

```bash
git add .
git commit -m "Update application"
git push origin cicd
```

GitHub Actions then:

```text
Push code
   ↓
Run workflow
   ↓
Authenticate using OIDC
   ↓
Build Docker images
   ↓
Push images to ECR
```

The EC2 deployment can then pull the updated images:

```bash
docker compose pull
docker compose up -d
```

Verify:

```bash
docker compose ps
```

---

# 19. Rollback

If a new Docker image causes a deployment problem, the previous image tag can be redeployed from ECR.

For production deployments, immutable image tags such as Git commit SHA values are recommended instead of relying only on:

```text
latest
```

Example:

```text
serphawk-backend:<commit-sha>
serphawk-frontend:<commit-sha>
```

This makes it possible to identify exactly which version is running on EC2.

---

# 20. Project Deployment Files

The deployment-related files include:

```text
.github/
└── workflows/
    └── deploy.yml

Dockerfile
docker-compose.yml
.env.example
```

The exact filenames may vary depending on the final repository structure.

These files define the application containerization and CI/CD deployment process.

---

# 21. Technology Stack

| Component               | Technology          |
| ----------------------- | ------------------- |
| Frontend                | Next.js 16          |
| UI                      | React 19            |
| Language                | TypeScript          |
| Styling                 | Tailwind CSS        |
| Backend                 | FastAPI             |
| Backend Language        | Python 3.13         |
| ORM                     | SQLModel            |
| Server                  | Uvicorn             |
| Real-time communication | WebSockets          |
| Database                | PostgreSQL          |
| Database Provider       | Neon                |
| Containers              | Docker              |
| Container Management    | Docker Compose      |
| CI/CD                   | GitHub Actions      |
| Container Registry      | Amazon ECR          |
| Compute                 | Amazon EC2          |
| AWS Authentication      | IAM + GitHub OIDC   |
| EC2 Management          | AWS Systems Manager |
| Source Control          | GitHub              |

---

# 22. Why This AWS Architecture Was Selected

## EC2

Provides direct control over the application server and supports the existing Docker Compose deployment model.

## ECR

Provides a private AWS-native registry for storing the backend and frontend Docker images.

## IAM

Provides controlled permissions for AWS resources.

## GitHub OIDC

Allows GitHub Actions to authenticate to AWS using temporary credentials instead of storing long-lived AWS access keys.

## Systems Manager

Provides secure EC2 management and command execution without requiring traditional SSH-based administration.

## Security Groups

Provide network-level access control for the EC2 instance.

## Neon PostgreSQL

Provides a managed PostgreSQL database without requiring the database server to be maintained directly on the EC2 instance.

---

# 23. End-to-End CI/CD Architecture

```text
                         ┌──────────────────┐
                         │    Developer     │
                         └────────┬─────────┘
                                  │
                              git push
                                  │
                                  ▼
                         ┌──────────────────┐
                         │     GitHub       │
                         │  cicd branch     │
                         └────────┬─────────┘
                                  │
                                  ▼
                       ┌──────────────────────┐
                       │   GitHub Actions     │
                       │      CI/CD           │
                       └──────────┬───────────┘
                                  │
                              OIDC Token
                                  │
                                  ▼
                       ┌──────────────────────┐
                       │      AWS IAM         │
                       │ github-actions-      │
                       │ ecr-push-role        │
                       └──────────┬───────────┘
                                  │
                         Temporary Credentials
                                  │
                                  ▼
                       ┌──────────────────────┐
                       │     Amazon ECR       │
                       │                      │
                       │  Backend   Frontend  │
                       └──────────┬───────────┘
                                  │
                              Pull Images
                                  │
                                  ▼
                       ┌──────────────────────┐
                       │       EC2            │
                       │                      │
                       │   Docker Compose     │
                       │                      │
                       │  ┌────────┐ ┌──────┐ │
                       │  │Next.js │ │FastAPI│ │
                       │  │ :3000  │ │ :8000 │ │
                       │  └────────┘ └───┬──┘ │
                       └──────────────────┼────┘
                                          │
                                          ▼
                               ┌──────────────────┐
                               │ Neon PostgreSQL  │
                               └──────────────────┘

                    AWS Systems Manager
                            │
                            ▼
                           EC2
```

---


---

# 25. Deployment Summary

The SERP Hawk CRM V2 application uses a containerized AWS deployment architecture.

Source code is maintained in GitHub. GitHub Actions automatically builds the frontend and backend Docker images and pushes them to Amazon ECR.

GitHub authenticates with AWS through OIDC and the `github-actions-ecr-push-role` IAM role, eliminating the need for long-lived AWS access keys.

The Docker images are deployed to an Amazon EC2 instance, where Docker Compose runs the frontend and backend containers.

AWS Systems Manager provides secure management of the EC2 instance, while Neon PostgreSQL provides the managed database service.

This architecture provides a straightforward containerized deployment with automated image delivery, controlled AWS permissions, and secure EC2 management.
