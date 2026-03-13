#!/usr/bin/env bun

import { existsSync } from "node:fs";
import { cp, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const [sourceDir, outputDir] = Bun.argv.slice(2);

if (!sourceDir || !outputDir) {
    console.error("Usage: bun Scripts/build-extension-resources.mjs <sourceDir> <outputDir>");
    process.exit(1);
}

const textFiles = [
    ["popup.html", minifyHTML],
    ["sidebar.html", minifyHTML],
    ["manifest.json", minifyJSON],
    ["sidebar-inject.js", (s) => s]
];

const isRelease = process.env.CONFIGURATION === "Release";

const buildResult = await Bun.build({
    entrypoints: [
        join(sourceDir, "background.js"),
        join(sourceDir, "content.js"),
        join(sourceDir, "popup.js"),
        join(sourceDir, "sidebar.js")
    ],
    outdir: outputDir,
    target: "browser",
    minify: isRelease,
    sourcemap: isRelease ? "none" : "inline"
});

if (!buildResult.success) {
    for (const log of buildResult.logs) {
        console.error(log);
    }
    process.exit(1);
}

await mkdir(join(outputDir, "images"), { recursive: true });
await buildTailwindCSS(join(sourceDir, "app.css"), join(outputDir, "app.css"));

for (const [relativePath, transform] of textFiles) {
    const source = await readFile(join(sourceDir, relativePath), "utf8");
    await writeFile(join(outputDir, relativePath), transform(source));
}

await syncDirectory(join(sourceDir, "images"), join(outputDir, "images"));

async function syncDirectory(sourceDirPath, outputDirPath) {
    await mkdir(outputDirPath, { recursive: true });
    const entries = await readdir(sourceDirPath, { withFileTypes: true });

    for (const entry of entries) {
        if (entry.name === ".DS_Store") {
            continue;
        }

        const sourcePath = join(sourceDirPath, entry.name);
        const outputPath = join(outputDirPath, entry.name);

        if (entry.isDirectory()) {
            await syncDirectory(sourcePath, outputPath);
            continue;
        }

        if (entry.isFile()) {
            await copyAsset(sourcePath, outputPath);
        }
    }
}

async function copyAsset(sourcePath, outputPath) {
    const extension = sourcePath.split(".").pop()?.toLowerCase();

    if (extension === "svg") {
        const svg = await readFile(sourcePath, "utf8");
        await writeFile(outputPath, minifySVG(svg));
        return;
    }

    await cp(sourcePath, outputPath, { force: true });
}

function minifyHTML(source) {
    return source
        .replace(/<!--[\s\S]*?-->/g, "")
        .replace(/>\s+</g, "><")
        .trim();
}

function minifyJSON(source) {
    return JSON.stringify(JSON.parse(source));
}

function minifySVG(source) {
    return source
        .replace(/<!--[\s\S]*?-->/g, "")
        .replace(/>\s+</g, "><")
        .replace(/\s{2,}/g, " ")
        .trim();
}

async function buildTailwindCSS(inputPath, outputPath) {
    const localTailwindCLI = join(process.cwd(), "node_modules", ".bin", "tailwindcss");
    const command = existsSync(localTailwindCLI)
        ? [localTailwindCLI, "-i", inputPath, "-o", outputPath, "--minify"]
        : [Bun.argv[0], "x", "@tailwindcss/cli", "-i", inputPath, "-o", outputPath, "--minify"];

    const childProcess = Bun.spawn({
        cmd: command,
        stderr: "inherit",
        stdout: "inherit"
    });

    const exitCode = await childProcess.exited;
    if (exitCode !== 0) {
        throw new Error("Tailwind CSS compilation failed.");
    }
}
