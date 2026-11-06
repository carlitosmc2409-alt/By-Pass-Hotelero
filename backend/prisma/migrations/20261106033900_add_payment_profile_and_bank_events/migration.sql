-- CreateEnum
CREATE TYPE "BankEventSource" AS ENUM ('SIMULATED', 'BDV_NOTIFICATION');

-- AlterTable
ALTER TABLE "guests" ADD COLUMN     "paymentBank" TEXT,
ADD COLUMN     "paymentCedula" TEXT,
ADD COLUMN     "paymentPhone" TEXT;

-- AlterTable
ALTER TABLE "hotels" ADD COLUMN     "paymentInfo" JSONB NOT NULL DEFAULT '{}';

-- AlterTable
ALTER TABLE "payments" ADD COLUMN     "amountVes" DECIMAL(14,2),
ADD COLUMN     "exchangeRate" DECIMAL(14,4),
ADD COLUMN     "expiresAt" TIMESTAMP(3),
ADD COLUMN     "reportedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "bank_events" (
    "id" TEXT NOT NULL,
    "hotelId" TEXT NOT NULL,
    "source" "BankEventSource" NOT NULL,
    "amountVes" DECIMAL(14,2) NOT NULL,
    "reference" TEXT NOT NULL,
    "payerPhone" TEXT,
    "payerCedula" TEXT,
    "payerBank" TEXT,
    "concept" TEXT,
    "rawText" TEXT,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "matchedPaymentId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "bank_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "bank_events_matchedPaymentId_key" ON "bank_events"("matchedPaymentId");

-- CreateIndex
CREATE INDEX "bank_events_hotelId_reference_idx" ON "bank_events"("hotelId", "reference");

-- CreateIndex
CREATE UNIQUE INDEX "payments_gateway_gatewayRef_key" ON "payments"("gateway", "gatewayRef");

-- AddForeignKey
ALTER TABLE "bank_events" ADD CONSTRAINT "bank_events_matchedPaymentId_fkey" FOREIGN KEY ("matchedPaymentId") REFERENCES "payments"("id") ON DELETE SET NULL ON UPDATE CASCADE;
