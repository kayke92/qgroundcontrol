#pragma once

#include <QtQuick/QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>
#include <QtCore/QVariantList>

class BathymetryRenderer : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList samples READ samples WRITE setSamples NOTIFY samplesChanged)
    Q_PROPERTY(qreal radiusPixels READ radiusPixels WRITE setRadiusPixels NOTIFY radiusPixelsChanged)
    Q_PROPERTY(qreal minimumDepth READ minimumDepth WRITE setMinimumDepth NOTIFY depthRangeChanged)
    Q_PROPERTY(qreal maximumDepth READ maximumDepth WRITE setMaximumDepth NOTIFY depthRangeChanged)

public:
    explicit BathymetryRenderer(QQuickItem* parent = nullptr);

    QVariantList samples() const { return _samples; }
    void setSamples(const QVariantList& samples);

    qreal radiusPixels() const { return _radiusPixels; }
    void setRadiusPixels(qreal radiusPixels);

    qreal minimumDepth() const { return _minimumDepth; }
    void setMinimumDepth(qreal depth);

    qreal maximumDepth() const { return _maximumDepth; }
    void setMaximumDepth(qreal depth);

    void paint(QPainter* painter) override;

signals:
    void samplesChanged();
    void radiusPixelsChanged();
    void depthRangeChanged();

private:
    QVariantList _samples;
    qreal _radiusPixels = 8.0;
    qreal _minimumDepth = 0.0;
    qreal _maximumDepth = 6.0;
};
