import { writeFile } from "node:fs/promises";
import { stringify } from "yaml";
import { openAPIDocument } from "../src/app";

await writeFile(new URL("../openapi.yaml", import.meta.url), stringify(openAPIDocument()), "utf8");
