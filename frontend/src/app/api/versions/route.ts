import { AppVersion } from "@/lib/types";
import { promises as fs } from "fs";
import { NextResponse } from "next/server";
import path from "path";

export const dynamic = "force-static";

const jsonDir = "public/json";
const versionsFileName = "versions.json";
const encoding = "utf-8";

const getVersions = async () => {
  const filePath = path.resolve(jsonDir, versionsFileName);
  console.log("TEST");
  console.log("FilePath: ", filePath);
  const fileContent = await fs.readFile(filePath, encoding);
  const versions: AppVersion = JSON.parse(fileContent);
  return versions;
};


export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const slug = searchParams.get("slug");

    if (!slug) {
      return NextResponse.json({ error: "Missing slug parameter" }, { status: 400 });
    }
    console.log("Slug: ", slug);
    const versions = await getVersions();

    const cleanedSlug = slug.toLowerCase().replace(/[^a-z0-9]/g, '');

    const matchedVersion = Object.values(versions).find(
      (version: AppVersion) => {
        const versionNameParts = version.name.split('/');
        const cleanedVersionName = versionNameParts[1]?.toLowerCase().replace(/[^a-z0-9]/g, '');
        return cleanedVersionName === cleanedSlug;
      }
    );

    return NextResponse.json(matchedVersion);
  } catch (error) {
    console.error(error);
    return NextResponse.json({name: "name", version: "No version found"});
  }
}
