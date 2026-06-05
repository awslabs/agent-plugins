# Common Best Practices

Best practices that apply to all model customization workflows regardless of model family.

## Data Preparation

- Always validate dataset format before training — catches errors before compute is spent
- Preview sample records at each transformation step to verify correctness
- Set a seed for train/val/test splits to ensure reproducibility
- Evaluation datasets require a different format than training datasets — validate each separately

## Training

- Start with smaller experiments before scaling to full datasets
- Monitor training logs proactively — don't wait for failure
- Save training results and checkpoints for later evaluation and deployment
- Use meaningful job names that include method, model, and date for tracking

## Evaluation

- Always evaluate model performance before deploying to production
- Compare against baseline model to quantify improvement
- Use evaluation datasets that represent real-world usage patterns

## Deployment

- Test with real-time inference on a dev endpoint before production deployment
- Delete unused endpoints to avoid unnecessary charges
- Document endpoint details and configuration for team reference

## General

- Define your use case and success criteria before starting any customization work
- Keep a record of what worked and what didn't for future reference
