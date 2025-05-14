# COM643-LiveDetection
Real-time detection of phishing/scam phone calls

## Structure
`liveprotector/` contains the example used during the first presentation of COM643
`liveprotector-backend/` contains the analysis software for the LLM comparison

## Datasets used
`datasets/call_transcripts_scam_determinations.csv` corresponds to https://www.kaggle.com/datasets/mealss/call-transcripts-scam-determinations 
`datasets/agent_conversation_test.csv` corresponds to https://huggingface.co/datasets/BothBosu/multi-agent-scam-conversation
for this last dataset, the label "innocent" has been replaced by "callee", and the label "suspect" has been replaced by "caller"
due to insights gained from https://dl.acm.org/doi/10.1145/3442188.3445922 ; indeed, original harmful associations present in the datasets, like "suspect" might bias the 
model into flagging calls as suspect. 