# README

# InsightStock | From a product return signal to a completed task

**Academic team concept and personal portfolio extension · Synthetic retail data**

A retail manager needs to decide which product issue deserves attention and who should investigate it. InsightStock brings sales, returns, customer comments and the decision log onto one dashboard. The manager can inspect the source evidence, assign a follow-up and track it through completion.

## One case from the demo

For the **Tundra Bottle, 1 liter**, customers returned 28 of 140 eligible units within the 30-day return window. That gives a historical return rate of **20.0%** for this variant and sales cohort. Separately, 10 of 50 reviews mentioned complaints. One excerpt reads, “Water leaked around the lid.” That observation gives the quality team a specific part to inspect. The underlying cause still needs investigation.

The manager chose **Investigate product issue** and assigned **Quality / supplier team**. An n8n workflow created the follow-up in Supabase. A second workflow sent a Telegram alert to the configured demo chat and recorded the send timestamp. The dashboard supported moving the task from **NEW** to **IN_PROGRESS** to **DONE**. The project owner confirmed that the final status persisted after reloading. Closing the demo task demonstrates the workflow. A supplier investigation and its outcome would require separate evidence.

## How the components fit together

| Component | Responsibility |
| --- | --- |
| Supabase / PostgreSQL | Stores nine imported product-variant snapshots, checks SKU and cohort consistency, calculates historical return rates, and retains the evidence behind each manager decision. |
| n8n and OpenRouter | Select pending synthetic review excerpts, request a complaint category and quotation, validate the response, and save the model and prompt version. |
| Manager dashboard | Shows the rule-based return signal, original excerpts and AI categories. The signed-in manager chooses the action and responsible team. |
| Follow-up workflows | Use the decision ID to prevent duplicate task records. Telegram delivery acknowledgment and task completion are tracked separately. |

## What I tested

- **Missing data.** Drift Hoodie has 95 eligible sales and an unknown return count. The dashboard displays an unavailable rate and withholds the score, while still showing that 9 of 30 reviews mentioned complaints.
- **Classifier behavior.** Both prompt versions matched the expected category on the same six synthetic evaluation examples, one per category. I also compared explanations to the original text. For example, the first prompt called failed stitching a manufacturing flaw. The revised prompt described the failure but added “of use,” a detail absent from the review.
- **Persistence and traceability.** I checked the saved decision, assigned team and Telegram send timestamp for Tundra Bottle. I used the dashboard to change the task status and checked the result after reload.
- **Coverage.** The product workflow processed 18 synthetic excerpts across nine variants. These excerpts illustrate individual comments. Complaint percentages use the separate review counts in the imported snapshots.

## My contribution and scope

InsightStock began as a university team project. For my portfolio extension, I configured Supabase and n8n, worked through the SQL checks, connected OpenRouter and Telegram, tested the classification outputs, and verified task persistence in the dashboard. I used AI assistance for implementation and troubleshooting. The six evaluation examples demonstrate the test procedure. Accuracy on real customer reviews and business impact remain unmeasured.

## Run the demo in your own project

1. Create a confirmed Supabase Auth manager user. In SQL Editor, run database/00_raw_schema.sql, then import data/product_snapshots.csv into product_snapshots_raw. Preserve the empty returns cell as SQL NULL.
2. Set the manager email in database/01_analysis_and_decisions.sql. Run SQL files 01 through 06 in numerical order as project administrator.
3. In app/index.html, replace YOUR_PROJECT_REF and YOUR_PUBLISHABLE_KEY with the project’s reference and public client key. Open the HTML and sign in as the manager.
4. Import the four JSON files from workflows/ into n8n. Replace each example Supabase hostname with your project hostname. For Supabase nodes, select an n8n Header Auth credential with header name apikey and the backend secret as its value. For OpenRouter nodes, use a separate Header Auth credential with Authorization and Bearer followed by a space and your key. Configure the Telegram credential and chat ID in workflow 02.
5. Run workflow 03 to compare six labeled examples with the classifier output. Run workflow 04 to classify at most 14 pending product excerpts per execution. On the fresh nine-row dataset, two successful runs cover all 18 excerpts. Reload the dashboard to see the labels.
6. Save a manager decision, run workflow 01 to create the task, then workflow 02 to send the demo notification. Reload Decision log, select Start task, then Mark done. Reload again to verify the persisted status. Workflows 01 and 02 include schedule triggers for use after configuration. Workflows 03 and 04 use manual triggers.