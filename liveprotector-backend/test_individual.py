from langchain_community.document_loaders import CSVLoader
from langchain_core.prompts import PromptTemplate
from langchain_text_splitters import RecursiveCharacterTextSplitter
from os.path import join, exists
from langchain_openai import AzureChatOpenAI, AzureOpenAIEmbeddings
from langchain_chroma import Chroma
from csv import DictReader, DictWriter
from copy import copy

ENDPOINT = "http://127.0.0.1:1234/v1"
MODELS = ('gemma-3-1b-it-qat', 'qwen3-1.7b', 'deepseek-r1-distill-qwen-1.5b')

embeddings = AzureOpenAIEmbeddings(
    azure_endpoint=ENDPOINT, 
    api_key="lm_studio"
)

vector_store = Chroma(
    collection_name="com643_collection",
    embedding_function=embeddings,
    persist_directory=join(".", "chroma_langchain_db"),
)

if (not exists(join(".", "chroma_langchain_db"))):
    # Load and chunk contents of the dataset
    docs = CSVLoader(file_path=join('..', 'datasets', 'call_transcripts_scam_determinations.csv'),
        csv_args={
            'delimiter': ',',
            'quotechar': '"',
            'fieldnames': ['CONVERSATION_ID', 'CONVERSATION_STEP', 'TEXT', 'CONTEXT', 'LABEL', 'FEATURES', 'ANNOTATIONS']
        }
    )

    text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
    all_splits = text_splitter.split_documents(docs)

    # Index chunks
    _ = vector_store.add_documents(documents=all_splits)

# Define prompt for question-answering
# Based of http://arxiv.org/abs/2502.03964
binary_classification_prompt = PromptTemplate.from_template("" \
    "Please analyze the call content and detect whether it is a fraud call." \
    "Please carefully analyze the suspicious features in the conversation. " \
    "If it is a fraud call, please only return \"FRAUD\". " \
    "If it is a normal call, please only return \"SAFE\". " \
    "Do not return anything else: {ongoing_conversation}")
uncertain_option_prompt = PromptTemplate.from_template("" \
    "Please analyze the call content and detect whether it is a fraud call. " \
    "Please carefully analyze the suspicious features in the conversation. " \
    "If it is a fraud call, please only return \"FRAUD\". " \
    "If it is a normal call, please only return \"SAFE\". " \
    "If there is insufficient information (e.g., it is not yet obvious that the fraud is present), please return \"UNCERTAIN\". " \
    "Do not return anything else: {ongoing_conversation}" \
    "Here is the context: {context}")

original_calls = DictReader(
    open(join('datasets', 'agent_conversation_test.csv')), 
    fieldnames=("dialog", "personality", "type", "scam?")
)

def verify_conversation_real_time(conversation: str, with_rag: bool, llm: AzureChatOpenAI) -> str:
    ongoing_conversation = ""

    for conversation_chunk in conversation.replace("Callee: ", "\nCallee: ").replace("Caller: ", "\nCaller: ").splitlines()[1:]:
        ongoing_conversation += conversation_chunk

        context = ''
        if with_rag:
            retrieved_docs = vector_store.similarity_search(conversation_chunk)
            docs_content = "\n\n".join(doc.page_content for doc in retrieved_docs)
            context = docs_content

        prompt = binary_classification_prompt.invoke({"ongoing_conversation": ongoing_conversation, "context": context})
        answer = llm.invoke(prompt)()
        if (answer == 'FRAUD'):
            return answer

    return 'SAFE'

def verify_conversation_real_time_option(conversation: str, with_rag: bool, llm: AzureChatOpenAI) -> str:
    ongoing_conversation = ""

    for conversation_chunk in conversation.replace("Callee: ", "\nCallee:").replace("Caller: ", "\nCaller:").splitlines()[1:]:
        ongoing_conversation += conversation_chunk

        context = ''
        if with_rag:
            retrieved_docs = vector_store.similarity_search(conversation_chunk)
            docs_content = "\n\n".join(doc.page_content for doc in retrieved_docs)
            context = docs_content

        prompt = uncertain_option_prompt.invoke({"ongoing_conversation": ongoing_conversation, "context": context})
        answer = llm.invoke(prompt)()
        if (answer == 'FRAUD'):
            return answer

    return answer

def run_analysis_for_model(model_name: str):
    print("Running analysis for model: " + model_name)

    llm = AzureChatOpenAI(
        api_version="",
        azure_endpoint=ENDPOINT,
        model=model_name,
        api_key="lm_studio"
    )
    count = 0
    calls_copy = copy(original_calls)

    # to skip the header
    next(calls_copy)
    
    for call in calls_copy:
        count += 1
        call["id"] = count

        print("Analysing call n°" + str(count))

        call["rt"] = verify_conversation_real_time(call['dialog'], False,  llm)
        call["unc"] = verify_conversation_real_time_option(call['dialog'], False, llm)
        call["rag_rt"] = verify_conversation_real_time(call['dialog'], True, llm)
        call["rag_unc"] = verify_conversation_real_time_option(call['dialog'], True, llm)

        print("Call n° analysed, rt: {}, unc: {}, rag_rt: {}, rag_unc: {}".format(call["rt"], call["unc"], call["rag_rt"], call["rag_unc"]))

    with open("results_" + model_name, mode='w', newline='') as file:
        print("Exporting results for model: " + model_name)

        writer = DictWriter(file, fieldnames=["dialog", "personality", "type", "scam?", "id", "rt", "unc"])
        writer.writeheader()
        writer.writerows(calls_copy)
    # Doesn't make sense because we have no previous study to compare to
    #call["ret"] = verify_conversation_retrospectively(call['dialog']) 

for model_name in MODELS:
    run_analysis_for_model(model_name)