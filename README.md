# SERP Hawk CRM V2

AI-Powered CRM for SEO Agencies | Next.js + FastAPI + PostgreSQL + Google Gemini

## Overview

SERP Hawk CRM V2 is a comprehensive customer relationship management system designed specifically for SEO agencies and digital marketing firms. It manages the entire client lifecycle from cold outreach to project delivery, billing, and SEO monitoring.

### Key Features

- **Role-Based Access**: Admin, Employee, Intern, Client roles with appropriate permissions
- **AI Email Agent**: Automated company research and personalized email generation
- **Real-Time Messaging**: WebSocket-based chat system
- **Service Management**: Catalog, quotes, invoicing, and billing
- **SEO Tools**: Keyword rankings, competitor analysis, SEO audits
- **Document Management**: File uploads, OCR for business cards
- **Reporting**: PDF exports, monitoring dashboards

## Tech Stack

- **Frontend**: Next.js 16, React 19, TypeScript, Tailwind CSS 4, Framer Motion
- **Backend**: FastAPI (Python 3.12), SQLModel ORM, Uvicorn with WebSocket
- **Database**: PostgreSQL (Neon Serverless)
- **AI**: Google Gemini 2.0 Flash (swapped in from OpenAI — see note below)
- **Integrations**: Outlook SMTP/IMAP, Webhooks, ReportLab PDFs

> **Note on AI provider:** The original project used OpenAI's GPT-4o-mini, which requires a paid API key. For this deployment, `modules/llm_engine.py` was rewritten to use Google Gemini instead (which has a genuine free tier), while keeping the exact same function signatures (`analyze_content`, `generate_email`, `analyze_document`). This means the AI-powered features (email generation, content analysis, document OCR fallback) work out of the box with no paid dependency. Four other modules that call OpenAI directly (`market_analyzer.py`, `fallback_analyzer.py`, `serp_hawk_email.py`, `service_extractor.py`) were left as-is and are not currently wired to a working key — noted here for transparency.

---

## Live Deployment

This project is deployed on **AWS EC2** (single instance). See [Deployment Architecture](#deployment-architecture) below for the full reasoning behind this choice.

- **Frontend URL**: `http://<EC2_PUBLIC_IP>:3000`
- **Backend API**: `http://<EC2_PUBLIC_IP>:8000`
- **API Docs (Swagger)**: `http://<EC2_PUBLIC_IP>:8000/docs`

---

## Deployment Architecture

### What was actually deployed

A **single AWS EC2 instance** (Ubuntu 24.04 LTS, t2/t3.micro — AWS Free Tier eligible) runs both the FastAPI backend and the Next.js frontend as persistent `systemd` services. The database is **Neon** (managed serverless PostgreSQL), not AWS RDS, to reduce moving parts and cost.

```
                        Internet
                            │
                            ▼
                 ┌─────────────────────┐
                 │   EC2 Security Group │
                 │  (least-privilege)    │
                 │  22  → My IP only     │
                 │  80/443 → Anywhere    │
                 │  3000 → Anywhere      │
                 │  8000 → Anywhere      │
                 └──────────┬───────────┘
                            │
                 ┌──────────▼───────────┐
                 │   EC2 (Ubuntu 24.04)  │
                 │   t2/t3.micro          │
                 │                        │
                 │  systemd: frontend     │
                 │   Next.js  :3000       │
                 │                        │
                 │  systemd: backend      │
                 │   FastAPI/Uvicorn:8000 │
                 └──────────┬───────────┘
                            │
                            ▼
                 ┌───────────────────────┐
                 │   Neon PostgreSQL      │
                 │  (managed, serverless) │
                 └───────────────────────┘
```

### AWS services used and why

| Service | Purpose | Justification |
|---|---|---|
| **EC2 (t2/t3.micro)** | Hosts both frontend and backend | Free Tier eligible; simplest way to run a full-stack app end-to-end within a short deployment window, without the cost/complexity of ECS, EKS, or Elastic Beanstalk for a project this size |
| **Security Groups** | Firewall rules | Configured with least privilege — SSH (port 22) restricted to a single IP instead of the internet, rather than left open to `0.0.0.0/0` |
| **systemd** | Process management | Runs both the frontend and backend as background services that auto-restart on crash and survive SSH disconnects/reboots, instead of relying on a terminal staying open |
| **Neon (PostgreSQL)** | Database | Free-tier managed Postgres; avoided provisioning RDS to keep the deployment lean and avoid additional Free Tier hour/storage tracking |

### Why a single EC2 instance (and not a full HA setup)

For a real production system with real user traffic, the right architecture would look different: an **Application Load Balancer** distributing traffic across **EC2 instances in an Auto Scaling Group spanning two Availability Zones**, with the backend and database placed in **private subnets** (not directly internet-facing), a **NAT Gateway** for outbound access, **Multi-AZ RDS** for the database, and **Secrets Manager** for credentials instead of a `.env` file.

That setup was deliberately not built here, for two reasons:

1. **Cost** — an ALB, NAT Gateway, and Multi-AZ RDS all fall outside AWS Free Tier and would add roughly $60–80/month in fixed costs for an app with no live traffic yet.
2. **Time** — provisioning a multi-AZ VPC, subnet routing, and load balancer chain takes meaningfully longer to build and debug correctly than a single-instance deployment.

The single-EC2 approach was chosen as the pragmatic trade-off: it demonstrates a working, secured, persistent deployment now, while the HA design above is the documented next step once the app has real traffic to justify the added cost and complexity.

### Known limitation

The EC2 instance currently uses a standard (non-Elastic) public IP, which can change if the instance is stopped and restarted. For a longer-lived production deployment, this would be replaced with an Elastic IP (or, better, a Route 53 domain name pointing at the load balancer in the HA design above) so the address never changes.

---

## Local Development Setup

### Prerequisites

- Node.js 18+
- Python 3.12+
- A PostgreSQL database (Neon recommended)
- Google Gemini API key (free tier: [aistudio.google.com](https://aistudio.google.com/app/apikey))

### Backend

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python create_tables.py
uvicorn main:app --reload
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```

### Environment Variables

Create a `.env` file in the project root:

```
DATABASE_URL=postgresql://user:password@host:port/database
GEMINI_API_KEY=your_gemini_key
OPENAI_API_KEY=            # optional — only needed if you re-enable OpenAI-based modules
SECRET_KEY=your_secret_key
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000   # local development
```

For the deployed frontend, `frontend/.env.local` sets:

```
NEXT_PUBLIC_API_BASE_URL=http://<EC2_PUBLIC_IP>:8000
```

**Note:** `.env` and `.env.local` are excluded from version control via `.gitignore` and are never committed.

---

## Production Deployment Steps (EC2)

These are the actual steps used to deploy this project to AWS:

1. Launch an EC2 instance (Ubuntu 24.04 LTS, t2/t3.micro) with a security group restricting SSH to a single IP and opening ports 80, 443, 3000, and 8000.
2. SSH into the instance and install Python 3.12, `python3-venv`, Git, and Node.js 20.
3. Transfer the project code (excluding `node_modules`, `.venv`, and build artifacts) via `scp`.
4. Set up the Python virtual environment and install backend dependencies.
5. Create `.env` with the Neon database URL and Gemini API key.
6. Run the backend as a persistent `systemd` service (`serphawk-backend.service`) bound to `0.0.0.0:8000`.
7. Install frontend dependencies, add a 1–2GB swapfile (needed for the Next.js production build to complete on a memory-constrained t2.micro), and run `npm run build`.
8. Set `NEXT_PUBLIC_API_BASE_URL` in `frontend/.env.local` to the EC2 instance's public IP.
9. Run the frontend as a persistent `systemd` service (`serphawk-frontend.service`) bound to `0.0.0.0:3000`.
10. Verify both services survive SSH disconnects and auto-restart on crash (`systemctl status`).

---

## How to Add New Features

### Backend (FastAPI)

1. **Add Database Models**:
   - Edit `database.py` to add new SQLModel classes
   - Run `python create_tables.py` to create tables

2. **Create API Endpoints**:
   - Add routes in `main.py` or create new modules
   - Follow RESTful conventions
   - Add proper authentication/authorization

3. **Add Business Logic**:
   - Create functions in appropriate modules under `modules/`
   - Use dependency injection for database sessions

4. **Update Dependencies**:
   - Add to `requirements.txt`
   - Test with `pip install -r requirements.txt`

### Frontend (Next.js)

1. **Create New Pages**:
   - Add to `frontend/src/app/` following the routing structure
   - Use TypeScript for type safety

2. **Add Components**:
   - Create reusable components in `frontend/src/components/`
   - Follow existing patterns for consistency

3. **API Integration**:
   - Use the existing API utilities in `frontend/src/lib/`
   - Add new API calls as needed

4. **Styling**:
   - Use Tailwind CSS classes
   - Follow the design system

## API Documentation

The API documentation is available at `/docs` when the backend is running (Swagger UI) and `/redoc` for ReDoc.

## License

This project is proprietary. All rights reserved.
