package com.booster.personallocation.service;

import com.booster.personallocation.domain.PersonalLocation;
import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.dto.LocationResponse;
import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.shared.common.BusinessException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class PersonalLocationService {

    private final PersonalLocationRepository personalLocationRepository;

    /** 최초 1회 등록. 이미 등록되어 있으면 409. */
    @Transactional
    public LocationResponse register(Long userId, LocationRequest request) {
        if (personalLocationRepository.existsById(userId)) {
            throw BusinessException.conflict("LOCATION_ALREADY_REGISTERED",
                    "이미 등록된 위치가 있습니다. 수정 API를 사용하세요.");
        }
        PersonalLocation saved = personalLocationRepository.save(PersonalLocation.create(
                userId, request.lat(), request.lng(), request.radiusMeters(), request.placeName()));
        return LocationResponse.from(saved);
    }

    /** 등록된 위치 수정. 미등록 시 404. */
    @Transactional
    public LocationResponse update(Long userId, LocationRequest request) {
        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound(
                        "LOCATION_NOT_FOUND", "등록된 위치가 없습니다."));
        location.update(request.lat(), request.lng(), request.radiusMeters(), request.placeName());
        return LocationResponse.from(location);
    }

    @Transactional(readOnly = true)
    public LocationResponse get(Long userId) {
        PersonalLocation location = personalLocationRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound(
                        "LOCATION_NOT_FOUND", "등록된 위치가 없습니다."));
        return LocationResponse.from(location);
    }
}
