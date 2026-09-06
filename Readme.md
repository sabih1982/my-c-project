# My C Project

A simple calculator project with CI/CD pipeline.

## Local Development

### Build
```bash
make
Test
bash
make tests
Run
bash
./calculator
Docker
bash
docker build -t my-c-app .
docker run --rm my-c-app
CI/CD Pipeline
This project uses GitHub Actions for:

Build verification

Unit testing

Docker image building

Automatic deployment (on main branch)

Project Structure
text
.
├── .github/
│   └── workflows/
│       └── ci.yml
├── tests/
│   ├── test_calculator.c
│   └── run_tests
├── calculator.c
├── calculator.h
├── main.c
├── Makefile
├── Dockerfile
└── README.md
text

### Step 11: Push Everything to GitHub
```powershell
git add .
git commit -m "Add CI/CD pipeline and Docker support"
git push