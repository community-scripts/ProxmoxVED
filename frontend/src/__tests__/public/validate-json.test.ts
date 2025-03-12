import { describe, it, assert, beforeAll } from "vitest";
import { promises as fs } from "fs";
import path from "path";
import { ScriptSchema, type Script } from "@/app/json-editor/_schemas/schemas";
import { Metadata } from "@/lib/types";

const jsonDir = "public/json";
const metadataFileName = "metadata.json";
const encoding = "utf-8";

let fileNames: string[] = [];

try {
  // Prüfen, ob das Verzeichnis existiert, falls nicht, Tests überspringen
  fileNames = (await fs.readdir(jsonDir)).filter((fileName) => fileName !== metadataFileName);
} catch (error) {
  console.warn(`Skipping JSON validation tests: ${error.message}`);
}

if (fileNames.length > 0) {
  describe.each(fileNames)("%s", async (fileName) => {
    let script: Script;

    beforeAll(async () => {
      const filePath = path.resolve(jsonDir, fileName);
      const fileContent = await fs.readFile(filePath, encoding);
      script = JSON.parse(fileContent);
    });

    it("should have valid json according to script schema", () => {
      ScriptSchema.parse(script);
    });

    it("should have a corresponding script file", async () => {
      for (const method of script.install_methods) {
        const scriptPath = path.resolve("..", method.script);
        try {
          await fs.stat(scriptPath);
        } catch {
          assert.fail(`Script file not found: ${scriptPath}`);
        }
      }
    });
  });

  describe(`${metadataFileName}`, async () => {
    let metadata: Metadata;

    beforeAll(async () => {
      const filePath = path.resolve(jsonDir, metadataFileName);
      const fileContent = await fs.readFile(filePath, encoding);
      metadata = JSON.parse(fileContent);
    });

    it("should have valid json according to metadata schema", () => {
      assert(metadata.categories.length > 0);
      metadata.categories.forEach((category) => {
        assert.isString(category.name);
        assert.isNumber(category.id);
        assert.isNumber(category.sort_order);
      });
    });
  });
} else {
  console.warn("Skipping tests because no JSON files were found.");
}
