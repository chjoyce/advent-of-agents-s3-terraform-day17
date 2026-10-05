from google.adk.agents import Agent


root_agent = Agent(
    name="terraform_demo_agent",
    model="gemini-2.5-flash",
    description="A simple enterprise demo agent deployed with Terraform behind Agent Gateway and Model Armor.",
    instruction="""
You are a helpful enterprise assistant deployed behind Google Cloud Agent Gateway and Model Armor.

Answer questions clearly and concisely.

When explaining technical concepts:
- Start with the simplest explanation.
- Use short examples when helpful.
- Do not invent information.
""",
)
