import boto3
import csv
import re
from io import StringIO

s3 = boto3.client("s3")
textract = boto3.client("textract")

def lambda_handler(event, context):
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = event["Records"][0]["s3"]["object"]["key"]
    OUTPUT_BUCKET = "imrs-textract-poojitha-output"

    # Run Textract
    response = textract.analyze_document(
        Document={"S3Object": {"Bucket": bucket, "Name": key}},
        FeatureTypes=["FORMS", "TABLES"]
    )

    blocks = response["Blocks"]

    # 26-column structure
    fields = [
        "category","kingdom","phylum","phylum_common_name","sub_phylum",
        "sub_phylum_common_name","class_name","class_common_name","sub_class",
        "sub_class_common_name","order_name","order_common_name","sub_order",
        "sub_order_common_name","family","family_common_name","sub_family",
        "sub_family_common_name","genus","species","authorship",
        "collectors_field_numbers","note","species_common_name","records"
    ]

    latin_pattern = r"^[A-Z][a-z]+ [a-z]+$"
    family_pattern = r".*IDAE$"
    category_pattern = r"^(Mammals|Birds|Reptiles|Amphibians|Fish|Insects|Plants)"

    rows = []
    current = {f:"" for f in fields}

    # Parse Textract blocks
    for block in blocks:
        if block["BlockType"] != "LINE":
            continue

        text = block["Text"].strip()

        # Detect category
        if re.match(category_pattern, text):
            current["category"] = text
            continue

        # Detect family
        if re.match(family_pattern, text):
            current["family"] = text
            continue

        # Detect Genus species
        if re.match(latin_pattern, text):
            if current["genus"]:
                rows.append(current.copy())
                current = {f:"" for f in fields}

            g, s = text.split()
            current["genus"] = g
            current["species"] = s
            continue

        # Common name
        if current["genus"] and not current["species_common_name"] and text[0].isupper():
            current["species_common_name"] = text
            continue

        # Everything else = records
        current["records"] += " " + text

    rows.append(current)

    # Convert to CSV
    csv_buf = StringIO()
    writer = csv.DictWriter(csv_buf, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

    # Upload CSV
    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key="IMRS_species.csv",
        Body=csv_buf.getvalue().encode("utf-8")
    )

    return {"status": "CSV created", "records": len(rows)}
