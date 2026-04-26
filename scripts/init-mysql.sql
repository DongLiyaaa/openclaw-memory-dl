-- ═══════════════════════════════════════════
-- OpenClaw 业务数据库初始化
-- ═══════════════════════════════════════════

CREATE DATABASE IF NOT EXISTS openclaw_business
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE openclaw_business;

-- ─── 广告活动表 ───
CREATE TABLE IF NOT EXISTS ad_campaigns (
    id INT AUTO_INCREMENT PRIMARY KEY,
    campaign_id VARCHAR(64) NOT NULL,
    campaign_name VARCHAR(256),
    campaign_type VARCHAR(32),
    marketplace VARCHAR(16),
    start_date DATE,
    end_date DATE,
    budget DECIMAL(12,2),
    currency VARCHAR(8),
    status VARCHAR(16),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_campaign_id (campaign_id),
    INDEX idx_marketplace (marketplace),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── 广告指标表 (日粒度) ───
CREATE TABLE IF NOT EXISTS ad_metrics_daily (
    id INT AUTO_INCREMENT PRIMARY KEY,
    campaign_id VARCHAR(64) NOT NULL,
    date DATE NOT NULL,
    impressions INT DEFAULT 0,
    clicks INT DEFAULT 0,
    spend DECIMAL(12,2) DEFAULT 0,
    sales DECIMAL(12,2) DEFAULT 0,
    orders INT DEFAULT 0,
    acos DECIMAL(8,4) DEFAULT 0,
    roas DECIMAL(8,4) DEFAULT 0,
    ctr DECIMAL(8,4) DEFAULT 0,
    cvr DECIMAL(8,4) DEFAULT 0,
    cpc DECIMAL(8,4) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_campaign_date (campaign_id, date),
    INDEX idx_date (date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── 产品/ASIN 表 ───
CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    asin VARCHAR(16) NOT NULL,
    msku VARCHAR(64),
    title VARCHAR(512),
    marketplace VARCHAR(16),
    category VARCHAR(128),
    price DECIMAL(10,2),
    status VARCHAR(16),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_asin_marketplace (asin, marketplace)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── 业务指标表 (日粒度) ───
CREATE TABLE IF NOT EXISTS business_metrics_daily (
    id INT AUTO_INCREMENT PRIMARY KEY,
    asin VARCHAR(16) NOT NULL,
    date DATE NOT NULL,
    sessions INT DEFAULT 0,
    page_views INT DEFAULT 0,
    units_ordered INT DEFAULT 0,
    sales DECIMAL(12,2) DEFAULT 0,
    unit_session_pct DECIMAL(8,4) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_asin_date (asin, date),
    INDEX idx_date (date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── 关键词表 ───
CREATE TABLE IF NOT EXISTS keywords (
    id INT AUTO_INCREMENT PRIMARY KEY,
    keyword VARCHAR(256) NOT NULL,
    marketplace VARCHAR(16),
    search_volume INT DEFAULT 0,
    relevance_score DECIMAL(4,2),
    source VARCHAR(32),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_keyword (keyword),
    INDEX idx_marketplace (marketplace)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── 系统日志表 ───
CREATE TABLE IF NOT EXISTS system_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(64) NOT NULL,
    source VARCHAR(64),
    message TEXT,
    severity VARCHAR(16) DEFAULT 'INFO',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_event_type (event_type),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
