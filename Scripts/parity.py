#!/usr/bin/env python3
"""Runs every merge case through `docker compose -f ... config --format json` and writes the results as a Swift
fixture (Tests/ComposeMergeClaimKitTests/ParityFixture.swift). The kit's merge must give the same canonical line per
service. Needs Docker Compose; run from the package root: python3 Scripts/parity.py"""
import json, os, random, subprocess, sys, tempfile

def canonical(service, project):
    def rel(path):
        if path.startswith(project + "/"):
            return "./" + path[len(project) + 1:]
        return path
    parts = ["image=" + service.get("image", "")]
    for key in ("command", "entrypoint"):
        if key in service and service[key] is not None:
            parts.append(key + "=" + json.dumps(service[key], separators=(",", ":")))
    ports = sorted("%s|%s|%s|%s" % (p.get("host_ip", ""), p.get("published", ""), p["target"], p["protocol"])
                   for p in service.get("ports", []))
    parts.append("ports=" + ",".join(ports))
    env = sorted(k if v is None else "%s=%s" % (k, v) for k, v in (service.get("environment") or {}).items())
    parts.append("env=" + ",".join(env))
    vols = sorted("%s<-%s" % (v["target"], rel(v.get("source", ""))) for v in service.get("volumes", []))
    parts.append("volumes=" + ",".join(vols))
    parts.append("expose=" + ",".join(service.get("expose", [])))
    parts.append("dns=" + ",".join(service.get("dns", []) or []))
    labels = sorted("%s=%s" % kv for kv in (service.get("labels") or {}).items())
    parts.append("labels=" + ",".join(labels))
    parts.append("depends=" + ",".join(sorted((service.get("depends_on") or {}).keys())))
    if "healthcheck" in service:
        parts.append("test=" + json.dumps(service["healthcheck"].get("test"), separators=(",", ":")))
    return ";".join(parts)

def run(files):
    with tempfile.TemporaryDirectory(dir="/tmp") as root:
        root = os.path.realpath(root)
        names = []
        for index, text in enumerate(files):
            name = "f%d.yaml" % index
            with open(os.path.join(root, name), "w") as handle:
                handle.write(text)
            names.append(name)
        args = ["docker", "compose"]
        for name in names:
            args += ["-f", name]
        env = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"]}
        out = subprocess.run(args + ["config", "--format", "json"], cwd=root, env=env, capture_output=True, text=True)
        if out.returncode != 0:
            return None
        project = json.loads(out.stdout)
        return {name: canonical(s, root) for name, s in sorted(project["services"].items())}

HAND = [
    ("ports appended", ["services:\n  web:\n    image: a\n    ports: [\"8080:80\"]\n",
                        "services:\n  web:\n    ports: [\"8081:80\"]\n"]),
    ("same port merged", ["services:\n  web:\n    image: a\n    ports: [\"8080:80\", \"9000:9000\"]\n",
                          "services:\n  web:\n    ports: [\"9000:9000\", \"8081:80\"]\n"]),
    ("port keys", ["services:\n  web:\n    image: a\n    ports: [\"8080:80\"]\n",
                   "services:\n  web:\n    ports:\n      - target: 80\n        published: \"8080\"\n      - \"127.0.0.1:8080:80\"\n      - \"8080:80/udp\"\n"]),
    ("empty list keeps", ["services:\n  web:\n    image: a\n    ports: [\"8080:80\"]\n    dns: [1.1.1.1]\n",
                          "services:\n  web:\n    ports: []\n    dns: []\n"]),
    ("reset list", ["services:\n  web:\n    image: a\n    ports: [\"8080:80\"]\n",
                    "services:\n  web:\n    ports: !reset []\n"]),
    ("override list", ["services:\n  web:\n    image: a\n    ports: [\"8080:80\"]\n",
                       "services:\n  web:\n    ports: !override\n      - \"8443:443\"\n"]),
    ("env merged", ["services:\n  web:\n    image: a\n    environment:\n      - DEBUG=0\n      - LOG=info\n",
                    "services:\n  web:\n    environment:\n      DEBUG: \"1\"\n      EXTRA: x\n"]),
    ("env reset key", ["services:\n  web:\n    image: a\n    environment: {DEBUG: \"1\", K: v}\n",
                       "services:\n  web:\n    environment:\n      DEBUG: !reset null\n"]),
    ("env override", ["services:\n  web:\n    image: a\n    environment: {DEBUG: \"1\", K: v}\n",
                      "services:\n  web:\n    environment: !override\n      NEW: \"1\"\n"]),
    ("env bare key", ["services:\n  web:\n    image: a\n    environment: [DEBUG=0, LOG=info]\n",
                      "services:\n  web:\n    environment: [LOG]\n"]),
    ("command replaced", ["services:\n  web:\n    image: a\n    command: [\"npm\", \"start\"]\n    entrypoint: [\"/e.sh\"]\n",
                          "services:\n  web:\n    command: npm run dev\n"]),
    ("command quoted", ["services:\n  web:\n    image: a\n    command: [\"a\"]\n",
                        "services:\n  web:\n    command: sh -c 'echo \"hi there\" && sleep 1'\n"]),
    ("command emptied", ["services:\n  web:\n    image: a\n    command: [\"a\", \"b\"]\n",
                         "services:\n  web:\n    command: []\n"]),
    ("entrypoint replaced", ["services:\n  web:\n    image: a\n    entrypoint: /a.sh\n",
                             "services:\n  web:\n    entrypoint: [\"/b.sh\", \"x\"]\n"]),
    ("healthcheck test", ["services:\n  web:\n    image: a\n    healthcheck:\n      test: [\"CMD\", \"a\"]\n      interval: 5s\n",
                          "services:\n  web:\n    healthcheck:\n      test: [\"CMD\", \"b\"]\n"]),
    ("image replaced", ["services:\n  web:\n    image: myapp:1.0\n", "services:\n  web:\n    image: myapp:dev\n"]),
    ("volumes by target", ["services:\n  web:\n    image: a\n    volumes: [\"./src:/app\", \"data:/data\"]\nvolumes:\n  data: {}\n",
                           "services:\n  web:\n    volumes: [\"./other:/app\", \"./cache:/cache\"]\n"]),
    ("volumes long", ["services:\n  web:\n    image: a\n    volumes: [\"./src:/app\"]\n",
                      "services:\n  web:\n    volumes:\n      - type: bind\n        source: ./x\n        target: /app\n"]),
    ("volumes override", ["services:\n  web:\n    image: a\n    volumes: [\"./src:/app\", \"./b:/b\"]\n",
                          "services:\n  web:\n    volumes: !override\n      - ./c:/c\n"]),
    ("labels merged", ["services:\n  web:\n    image: a\n    labels: [a=1, b=2]\n",
                       "services:\n  web:\n    labels:\n      b: \"3\"\n      c: \"4\"\n"]),
    ("depends merged", ["services:\n  web:\n    image: a\n    depends_on: [db]\n  db:\n    image: p\n  cache:\n    image: r\n",
                        "services:\n  web:\n    depends_on:\n      cache:\n        condition: service_started\n"]),
    ("expose and dns order", ["services:\n  web:\n    image: a\n    expose: [\"5000\"]\n    dns: [9.9.9.9]\n",
                              "services:\n  web:\n    expose: [\"3000\", \"5000\"]\n    dns: [1.1.1.1, 9.9.9.9]\n"]),
    ("new service", ["services:\n  web:\n    image: a\n", "services:\n  cache:\n    image: redis\n    ports: [\"6379:6379\"]\n"]),
    ("reset service", ["services:\n  web:\n    image: a\n  debug:\n    image: b\n", "services:\n  debug: !reset {}\n"]),
    ("override service", ["services:\n  web:\n    image: a\n    ports: [\"1:1\"]\n    environment: {A: \"1\"}\n",
                          "services:\n  web: !override\n    image: b\n"]),
    ("three files", ["services:\n  web:\n    image: one\n    ports: [\"80:80\"]\n    environment: {A: \"1\"}\n",
                     "services:\n  web:\n    image: two\n    ports: [\"81:80\"]\n    environment: {B: \"2\"}\n",
                     "services:\n  web:\n    image: three\n    environment: {A: \"3\"}\n"]),
    ("ephemeral port", ["services:\n  web:\n    image: a\n    ports: [\"80\"]\n", "services:\n  web:\n    ports: [\"80\", \"8080:80\"]\n"]),
    ("ipv6 binding", ["services:\n  web:\n    image: a\n    ports: [\"[::1]:8080:80\"]\n", "services:\n  web:\n    ports: [\"8080:80\"]\n"]),
    ("image reset", ["services:\n  web:\n    image: a\n    build: .\n", "services:\n  web:\n    image: !reset null\n"]),
    ("env list both", ["services:\n  web:\n    image: a\n    environment: [A=1, B=2]\n",
                       "services:\n  web:\n    environment: [B=3, C=4]\n"]),
]

def generated(count, seed=1123):
    rng = random.Random(seed)
    ports = ["8080:80", "8081:80", "9000:9000", "127.0.0.1:5432:5432", "5433:5432", "80", "3000:3000/udp"]
    envs = ["DEBUG=0", "DEBUG=1", "LOG=info", "LOG=debug", "API=http://api:8000", "TOKEN"]
    images = ["myapp:1.0", "myapp:dev", "nginx:1.27", "postgres:16"]
    commands = ["npm start", "npm run dev", "[\"python\", \"app.py\"]", "[]"]
    vols = ["./src:/app", "./other:/app", "data:/data", "./cache:/cache", "/var/run/docker.sock:/var/run/docker.sock"]
    cases = []
    for number in range(count):
        files = []
        for index in range(rng.choice([2, 2, 3])):
            lines = ["services:", "  web:"]
            if index == 0 or rng.random() < 0.5:
                lines.append("    image: " + rng.choice(images))
            if rng.random() < 0.5:
                lines.append("    command: " + rng.choice(commands))
            if rng.random() < 0.7:
                picked = rng.sample(ports, rng.randint(0, 3))
                tag = " !override" if index > 0 and rng.random() < 0.15 else ""
                lines.append("    ports:%s %s" % (tag, json.dumps(picked)))
            if rng.random() < 0.7:
                picked = rng.sample(envs, rng.randint(1, 3))
                names = []
                kept = [e for e in picked if not (e.split("=")[0] in names or names.append(e.split("=")[0]))]
                if rng.random() < 0.5:
                    lines.append("    environment: " + json.dumps(kept))
                else:
                    lines.append("    environment:")
                    for item in kept:
                        key, _, value = item.partition("=")
                        lines.append("      %s: %s" % (key, json.dumps(value) if value else "null"))
            if rng.random() < 0.4:
                picked = rng.sample(vols, rng.randint(1, 2))
                targets = []
                kept = [v for v in picked if not (v.split(":")[1] in targets or targets.append(v.split(":")[1]))]
                lines.append("    volumes: " + json.dumps(kept))
            if rng.random() < 0.3:
                lines.append("    dns: " + json.dumps(rng.sample(["1.1.1.1", "8.8.8.8", "9.9.9.9"], 2)))
            files.append("\n".join(lines) + "\n" + ("volumes:\n  data: {}\n" if any("data:/data" in l for l in lines) else ""))
        cases.append(("generated %d" % (number + 1), files))
    return cases

def swift_string(text):
    return json.dumps(text)

def main():
    cases = HAND + generated(int(sys.argv[1]) if len(sys.argv) > 1 else 50)
    out = ["// Generated by Scripts/parity.py from `docker compose -f ... config --format json`", "// (Docker Compose %s). Do not edit by hand." %
           subprocess.run(["docker", "compose", "version", "--short"], capture_output=True, text=True).stdout.strip(),
           "", "let parityCases: [(name: String, files: [String], services: [String: String])] = ["]
    kept = 0
    for name, files in cases:
        result = run(files)
        if result is None:
            print("refused by compose:", name, file=sys.stderr)
            continue
        kept += 1
        services = ", ".join("%s: %s" % (swift_string(k), swift_string(v)) for k, v in result.items())
        out.append("    (%s, [%s], [%s])," % (swift_string(name), ", ".join(swift_string(f) for f in files),
                                             services if services else ":"))
    out.append("]")
    with open("Tests/ComposeMergeClaimKitTests/ParityFixture.swift", "w") as handle:
        handle.write("\n".join(out) + "\n")
    print("cases:", kept, "of", len(cases))

main()
