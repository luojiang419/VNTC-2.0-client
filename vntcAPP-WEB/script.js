const revealTargets = document.querySelectorAll(".reveal");
const counterTargets = document.querySelectorAll("[data-count]");
const tiltTargets = document.querySelectorAll(".tilt-surface");
const spotlightTargets = document.querySelectorAll(".spotlight-card");
const progressBar = document.querySelector(".scroll-progress");
const copyButton = document.querySelector(".copy-button");
const releaseApiUrl =
  "https://api.github.com/repos/luojiang419/VNTC-2.0-client/releases/tags/v1.0.0";
const totalDownloadTargets = document.querySelectorAll(
  "[data-download-total], [data-download-count-total]",
);
const setupDownloadTarget = document.querySelector("[data-download-setup]");
const portableDownloadTarget = document.querySelector("[data-download-portable]");
const assetCountTargets = document.querySelectorAll("[data-download-count]");

const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) {
        return;
      }
      entry.target.classList.add("in-view");
      if (entry.target.hasAttribute("data-count")) {
        animateCounter(entry.target);
      }
      entry.target.querySelectorAll("[data-count]").forEach(animateCounter);
      revealObserver.unobserve(entry.target);
    });
  },
  {
    threshold: 0.18,
  },
);

revealTargets.forEach((target) => revealObserver.observe(target));

function animateCounter(element) {
  if (element.dataset.animated === "true") {
    return;
  }

  element.dataset.animated = "true";
  const endValue = Number(element.dataset.count);
  const start = performance.now();
  const duration = 1200;

  const step = (now) => {
    const progress = Math.min((now - start) / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3);
    element.textContent = `${Math.round(endValue * eased)}`;

    if (progress < 1) {
      requestAnimationFrame(step);
    }
  };

  requestAnimationFrame(step);
}

tiltTargets.forEach((element) => {
  element.addEventListener("pointermove", (event) => {
    const rect = element.getBoundingClientRect();
    const px = (event.clientX - rect.left) / rect.width;
    const py = (event.clientY - rect.top) / rect.height;
    const rotateY = (px - 0.5) * 9;
    const rotateX = (0.5 - py) * 9;
    element.style.transform = `perspective(1200px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-4px)`;
  });

  element.addEventListener("pointerleave", () => {
    element.style.transform = "";
  });
});

spotlightTargets.forEach((card) => {
  card.addEventListener("pointermove", (event) => {
    const rect = card.getBoundingClientRect();
    const x = `${event.clientX - rect.left}px`;
    const y = `${event.clientY - rect.top}px`;
    card.style.setProperty("--spot-x", x);
    card.style.setProperty("--spot-y", y);
  });
});

function updateScrollProgress() {
  const scrollTop = window.scrollY;
  const maxScroll = document.body.scrollHeight - window.innerHeight;
  const progress = maxScroll <= 0 ? 0 : (scrollTop / maxScroll) * 100;
  progressBar?.style.setProperty("--scroll-progress", `${progress}%`);
}

updateScrollProgress();
window.addEventListener("scroll", updateScrollProgress, { passive: true });

copyButton?.addEventListener("click", async () => {
  const groupId = copyButton.dataset.copy ?? "";

  try {
    await navigator.clipboard.writeText(groupId);
    copyButton.classList.add("is-copied");
    copyButton.textContent = "已复制群号";
    window.setTimeout(() => {
      copyButton.classList.remove("is-copied");
      copyButton.textContent = `复制群号 ${groupId}`;
    }, 1800);
  } catch (error) {
    copyButton.textContent = "复制失败，请手动复制";
    window.setTimeout(() => {
      copyButton.textContent = `复制群号 ${groupId}`;
    }, 1800);
  }
});

fetchReleaseDownloads().catch(() => {
  setDownloadFallback();
});

async function fetchReleaseDownloads() {
  const response = await fetch(releaseApiUrl, {
    headers: {
      Accept: "application/vnd.github+json",
    },
  });

  if (!response.ok) {
    throw new Error(`GitHub API ${response.status}`);
  }

  const release = await response.json();
  const assets = Array.isArray(release.assets) ? release.assets : [];
  const assetMap = new Map(
    assets.map((asset) => [asset.name, Number(asset.download_count ?? 0)]),
  );

  const setupCount =
    assetMap.get("VNTC-2.0-client-v1.0.0-setup.exe") ?? 0;
  const portableCount =
    assetMap.get("VNTC-2.0-client-v1.0.0-win-x64.zip") ?? 0;
  const totalCount = setupCount + portableCount;

  updateDownloadValue(setupDownloadTarget, setupCount);
  updateDownloadValue(portableDownloadTarget, portableCount);

  totalDownloadTargets.forEach((target) => {
    updateDownloadValue(target, totalCount);
  });

  assetCountTargets.forEach((target) => {
    const assetName = target.dataset.downloadCount;
    updateDownloadValue(target, assetMap.get(assetName) ?? 0);
  });
}

function updateDownloadValue(target, value) {
  if (!target) {
    return;
  }

  target.textContent = formatDownloadCount(value);
}

function setDownloadFallback() {
  updateDownloadValue(setupDownloadTarget, 0);
  updateDownloadValue(portableDownloadTarget, 0);

  totalDownloadTargets.forEach((target) => {
    if (target) {
      target.textContent = "获取失败";
    }
  });

  assetCountTargets.forEach((target) => {
    if (target) {
      target.textContent = "获取失败";
    }
  });
}

function formatDownloadCount(value) {
  return `${Number(value || 0).toLocaleString("zh-CN")} 次`;
}
