# InsightStock

InsightStock is a retail returns dashboard that brings together sales,
returns, stock levels, and customer feedback. Managers can review product
evidence, record a decision, and assign a follow-up through Telegram.

[Watch the 1-minute demo](./InsightStock%20demo.mov)

## Demo scenario

Nova Bag has a 2.5% historical return rate. A customer reports that the
zipper broke on first use. The dashboard shows the AI classification
`QUALITY_DEFECT` beside the quote. The manager assigns a follow-up to the
quality team, and n8n sends the task to Telegram.

## My contribution

I extended our university team prototype by connecting the dashboard to
Supabase, adding SQL data checks, and building n8n workflows for complaint
classification and Telegram notifications.

**Stack:** HTML, JavaScript, PostgreSQL, Supabase, n8n, OpenRouter, Telegram.

This portfolio prototype uses synthetic data.
