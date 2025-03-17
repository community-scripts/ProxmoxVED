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

    console.log("Matched Version: ", matchedVersion);
    if (!matchedVersion) {
      return NextResponse.json({name: "No version found", version: "No Version found"});
    }
    return NextResponse.json(matchedVersion);

  } catch (error) {
    return NextResponse.json({name: error, version: "No version found - Error"});
  }
}
