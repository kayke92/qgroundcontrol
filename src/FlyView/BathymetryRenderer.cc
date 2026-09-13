#include "BathymetryRenderer.h"

#include <QColor>
#include <QHash>
#include <QImage>
#include <QPainter>
#include <QVariantMap>
#include <QVector>

#include <algorithm>
#include <cmath>
#include <iterator>

namespace {

struct ScreenSample {
    qreal x;
    qreal y;
    qreal depth;
};

quint64 bucketKey(int x, int y)
{
    return (quint64(quint32(x)) << 32) | quint32(y);
}

QColor depthColor(qreal depth, qreal minimumDepth, qreal maximumDepth)
{
    struct Stop { qreal t; qreal r; qreal g; qreal b; };
    static constexpr Stop stops[] = {
        {0.00, 0.90, 0.12, 0.08},
        {0.18, 1.00, 0.45, 0.05},
        {0.36, 1.00, 0.85, 0.08},
        {0.54, 0.15, 0.78, 0.24},
        {0.72, 0.05, 0.72, 0.82},
        {1.00, 0.05, 0.20, 0.92},
    };

    const qreal span = std::max<qreal>(0.25, maximumDepth - minimumDepth);
    const qreal t = std::clamp((depth - minimumDepth) / span, 0.0, 1.0);

    for (size_t i = 0; i + 1 < std::size(stops); ++i) {
        const Stop& a = stops[i];
        const Stop& b = stops[i + 1];
        if (t >= a.t && t <= b.t) {
            const qreal u = (t - a.t) / std::max<qreal>(0.0001, b.t - a.t);
            return QColor::fromRgbF(a.r + (b.r - a.r) * u,
                                    a.g + (b.g - a.g) * u,
                                    a.b + (b.b - a.b) * u,
                                    1.0);
        }
    }
    return QColor::fromRgbF(0.05, 0.20, 0.92, 1.0);
}

} // namespace

BathymetryRenderer::BathymetryRenderer(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void BathymetryRenderer::setSamples(const QVariantList& samples)
{
    if (_samples == samples) {
        return;
    }
    _samples = samples;
    emit samplesChanged();
    update();
}

void BathymetryRenderer::setRadiusPixels(qreal radiusPixels)
{
    radiusPixels = std::max<qreal>(1.0, radiusPixels);
    if (qFuzzyCompare(_radiusPixels, radiusPixels)) {
        return;
    }
    _radiusPixels = radiusPixels;
    emit radiusPixelsChanged();
    update();
}

void BathymetryRenderer::setMinimumDepth(qreal depth)
{
    if (qFuzzyCompare(_minimumDepth, depth)) {
        return;
    }
    _minimumDepth = depth;
    emit depthRangeChanged();
    update();
}

void BathymetryRenderer::setMaximumDepth(qreal depth)
{
    if (qFuzzyCompare(_maximumDepth, depth)) {
        return;
    }
    _maximumDepth = depth;
    emit depthRangeChanged();
    update();
}

void BathymetryRenderer::paint(QPainter* painter)
{
    if (_samples.size() < 2 || width() < 2 || height() < 2) {
        return;
    }

    // Render op een lager intern raster en schaal daarna bilineair op.
    // Dit voorkomt zichtbare kaartvakjes en houdt Android-belasting beheersbaar.
    constexpr qreal renderScale = 0.34;
    const int imageWidth = std::max(1, int(std::ceil(width() * renderScale)));
    const int imageHeight = std::max(1, int(std::ceil(height() * renderScale)));
    const qreal radius = std::max<qreal>(1.5, _radiusPixels * renderScale);
    const qreal radiusSquared = radius * radius;
    const qreal fullAlphaRadius = radius * 0.72;

    QVector<ScreenSample> points;
    points.reserve(_samples.size());
    for (const QVariant& value : _samples) {
        const QVariantMap map = value.toMap();
        const qreal x = map.value(QStringLiteral("x")).toReal() * renderScale;
        const qreal y = map.value(QStringLiteral("y")).toReal() * renderScale;
        const qreal depth = map.value(QStringLiteral("depth")).toReal();
        if (std::isfinite(x) && std::isfinite(y) && std::isfinite(depth)) {
            points.append({x, y, depth});
        }
    }
    if (points.size() < 2) {
        return;
    }

    const qreal bucketSize = radius;
    QHash<quint64, QVector<int>> buckets;
    for (int i = 0; i < points.size(); ++i) {
        const int bx = int(std::floor(points[i].x / bucketSize));
        const int by = int(std::floor(points[i].y / bucketSize));
        buckets[bucketKey(bx, by)].append(i);
    }

    QImage image(imageWidth, imageHeight, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);

    for (int y = 0; y < imageHeight; ++y) {
        QRgb* scanLine = reinterpret_cast<QRgb*>(image.scanLine(y));
        const int bucketY = int(std::floor(qreal(y) / bucketSize));
        for (int x = 0; x < imageWidth; ++x) {
            const int bucketX = int(std::floor(qreal(x) / bucketSize));
            qreal weightedDepth = 0.0;
            qreal totalWeight = 0.0;
            qreal nearest = radius;

            for (int oy = -1; oy <= 1; ++oy) {
                for (int ox = -1; ox <= 1; ++ox) {
                    const auto it = buckets.constFind(bucketKey(bucketX + ox, bucketY + oy));
                    if (it == buckets.constEnd()) {
                        continue;
                    }
                    for (int index : it.value()) {
                        const ScreenSample& point = points[index];
                        const qreal dx = qreal(x) - point.x;
                        const qreal dy = qreal(y) - point.y;
                        const qreal distanceSquared = dx * dx + dy * dy;
                        if (distanceSquared <= radiusSquared) {
                            const qreal distance = std::sqrt(distanceSquared);
                            const qreal weight = 1.0 / std::max<qreal>(0.20, distanceSquared);
                            weightedDepth += point.depth * weight;
                            totalWeight += weight;
                            nearest = std::min(nearest, distance);
                        }
                    }
                }
            }

            if (totalWeight <= 0.0) {
                continue;
            }

            const qreal depth = weightedDepth / totalWeight;
            QColor color = depthColor(depth, _minimumDepth, _maximumDepth);
            qreal edgeAlpha = 1.0;
            if (nearest > fullAlphaRadius) {
                edgeAlpha = std::clamp((radius - nearest) /
                                       std::max<qreal>(0.01, radius - fullAlphaRadius), 0.0, 1.0);
            }
            color.setAlphaF(0.76 * edgeAlpha);
            scanLine[x] = qPremultiply(color.rgba());
        }
    }

    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(boundingRect(), image);
}
