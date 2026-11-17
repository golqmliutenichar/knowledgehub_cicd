"""Data model: one row per measured value."""

from datetime import datetime, timezone

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Measurement(db.Model):
    """A single metric value from one host at one moment (times stored in UTC)."""

    __tablename__ = "measurements"
    __table_args__ = (
        db.Index("ix_host_metric_time", "host", "metric", "measured_at"),
    )

    id = db.Column(db.BigInteger().with_variant(db.Integer, "sqlite"), primary_key=True)
    host = db.Column(db.String(100), nullable=False)
    metric = db.Column(db.String(50), nullable=False)
    value = db.Column(db.Float, nullable=False)
    unit = db.Column(db.String(20), nullable=False, default="%")
    measured_at = db.Column(db.DateTime, nullable=False)
    received_at = db.Column(db.DateTime, nullable=False, default=utc_now)

    def to_dict(self):
        return {
            "id": self.id,
            "host": self.host,
            "metric": self.metric,
            "value": self.value,
            "unit": self.unit,
            "measured_at": self.measured_at.isoformat() + "Z",
        }
