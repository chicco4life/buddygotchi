import { test, expect } from "@playwright/test";

test("price cohort shows and the waitlist flow lands on /welcome", async ({ page }) => {
  await page.goto("/?p=99&utm_source=test&utm_campaign=e2e");

  // Cohort price is reflected in the hero CTA.
  const cta = page.getByTestId("hero-cta");
  await expect(cta).toContainText("$99");

  // Opening the modal and submitting an email navigates to the welcome page.
  await cta.click();
  const email = `e2e+${Date.now()}@example.com`;
  await page.getByLabel("Email address").first().fill(email);
  await page.getByRole("button", { name: "Get in line" }).first().click();

  await page.waitForURL(/\/welcome/);
  await expect(page.getByRole("heading", { name: "You're in line." })).toBeVisible();

  // A position and a copyable referral link are present.
  await expect(page.getByLabel("Your referral link")).toHaveValue(/\/\?ref=/);

  // The optional price-expectation survey accepts an answer and swaps to thanks.
  await page
    .getByLabel("What would you honestly expect a buddy like this to cost?")
    .fill("$119");
  await page.getByRole("button", { name: "Send" }).click();
  await expect(page.getByText("Noted. The litter thanks you.")).toBeVisible();
});
